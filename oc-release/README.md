# Overclock + overvolt + desbloqueo térmico — Redmi 9C "angelica" (MT6765 / Helio G35)

Target: M2006C3MG, MIUI 12.5.9.0.RCDINXM, bootloader desbloqueado (`ro.boot.flash.locked=0`), sin root.
El recovery del móvil da **adb con root**, así que hay dos caminos de flasheo (fastboot y recovery).

Todo lo de abajo está **verificado contra el código fuente del kernel y contra el propio teléfono**
(segmento GPU = 3, CPU level = C65, tabla de frecuencias de MIUI = la `c65Tbl` de este repo,
y el `boot.img` real extraído de la partición `boot`).

---

## 0. Lo primero: qué hacer (3 pasos)

```bash
# 1) Compilar el kernel parcheado (GitHub Actions -> artefacto "Image.gz-...")
#    Ver seccion 4

# 2) Meter el kernel nuevo en el boot.img original (solo cambia el kernel;
#    el ramdisk y el DTB del fabricante se conservan byte a byte)
python oc-release/scripts/repack-boot.py \
    oc-release/backup/boot_stock.img \
    Image.gz \
    boot_oc.img

# 3) Flashear
bash oc-release/scripts/flash.sh boot_oc.img
```

Rollback en cualquier momento: `fastboot flash boot oc-release/backup/boot_stock.img`.

---

## 1. Qué hace el parche (5 archivos)

| Archivo | Cambio | Efecto real en el teléfono |
|---|---|---|
| `drivers/gpu/mediatek/gpufreq/mt6765/mtk_gpufreq_core.h` | `SEG3_GPU_DVFS_FREQ0: 880000 → 900000` | GPU: **900 MHz** (bin del propio móvil) |
| | `SEG3_GPU_DVFS_VOLT0: 80000 → 95000` | La pista de voltaje pasa a pedir el **escalón VCORE más alto** |
| | `POST_DIV_*_MAX/MIN_FREQ` restaurados | Arregla los valores que Codex había corrompido (×10 / ÷10) |
| `drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6765/mtk_cpufreq_opp_table.h` | `CPU_DVFS_FREQ0_L_C65: 2301000 → 2401000` | CPU: **2301 MHz → 2401 MHz** |
| | `CPU_DVFS_VOLT0_VPROC_L_C65: 111875 → 118750` | VPROC: **1.11875 V → 1.1875 V** |
| `.../mt6765/mtk_cpufreq_opp_pv_table.h` | `c65Tbl` fila 0: `{2301, 96}` → `{2401, 107}` | Mismo cambio en la tabla SRAM que usa el firmware SCP |
| `drivers/misc/mediatek/thermal/mt6765/inc/tzcpu_initcfg.h` | `TRIP_1..9`: 65/64/63/62/60/55/50/45/40 °C → **90/89/88/87/85/80/75/70/65 °C** | El *throttle* por software empieza 25 °C más tarde |
| `drivers/misc/mediatek/thermal/mt6765/inc/clatm_initcfg.h` | `TARGET_TJ` de CATM/PHPB: 75/65 → **90 °C**; `CLCTM_TARGET_TJ`: 90 → **95 °C** | El recorte por *power budget* también empieza mucho más tarde |

`TRIP_0` (117 °C) **no se toca**: es la protección de hardware (apagado de emergencia); moverla
sería jugar contra el silicio.

### Por qué te salían artifacts a 950 MHz (y por qué el perfil por defecto ya no llega a 950)

La columna `volt` de la tabla GPU **no es un voltaje**, es una *pista* que el driver traduce:

```c
/* drivers/gpu/mediatek/gpufreq/mt6765/mtk_gpufreq_core.c */
if (volt_target > 90000)      mtk_pm_qos_update_request(..., VCORE_OPP_0);        /* riel ALTO  */
else if (volt_target > 80000) mtk_pm_qos_update_request(..., VCORE_OPP_1 * 9 / 10);/* = OPP_0   */
else if (volt_target > 0)     mtk_pm_qos_update_request(..., VCORE_OPP_3 * 9 / 10);/* = OPP_2 (BAJO) */
```

`VCORE_OPP_0` es el escalón **más alto** porque `mtk_dvfsrc_vcore_uv_table()` invierte la tabla
del firmware (`vopp_uv_tlb[num_vopp - opp - 1]`). Con la pista de stock (**80000**) la GPU
quedaba clavada en el **riel más bajo**: medido en el teléfono, `Vcore : 650000 uv`.

Lo que dice el propio móvil con el kernel de MIUI (sin parche):

```
$ adb shell cat /proc/gpufreq/gpufreq_opp_dump
[0] freq = 900000, volt = 80000, vsram = 87500, gpufreq_power = 995
[1] freq = 500000, volt = 70000, ...
[2] freq = 400000, volt = 65000, ...

$ adb shell cat /proc/gpufreq/gpufreq_var_dump | grep -E 'vcore|opp_freq'
g_cur_opp_freq = 900000, g_cur_opp_volt = 80000, ...
current vcore opp = 0

$ adb shell cat '/sys/class/regulator/regulator.3/10012000.dvfsrc:dvfsrc-debug-vcore/dvfsrc_dump' | head -1
Vcore     : 800000   uv
```

O sea: la pista de stock es 80000 y con el driver de este repo eso cae en la rama
`VCORE_OPP_3 * 9 / 10` → **pide el riel más bajo** (650 mV medido con el kernel parcheado de
Codex). Subir la pista a 95000 fuerza la rama `VCORE_OPP_0` → **riel más alto** (≥ 800 mV).

Por eso:

- El perfil por defecto (P2) deja la GPU en **900 MHz** (el bin que el propio móvil usa) pero con
  el **riel VCORE en el escalón alto** (pista 95000). Es la combinación "sin artifacts".
- **950 MHz queda como opt-in (P3)**, ya con el riel alto. Si en P3 hay artifacts, es el silicio
  de tu lote, no la configuración.

Además, `POST_DIV_4_MAX_FREQ` estaba corrupto (`9500000` en vez de `950000`): el driver
comprueba el rango del divisor contra esos valores y, al estar ×10, el cálculo de DDS salía
mal. Restaurado.

### Por qué 950 MHz es el techo de la GPU
`__mt_gpufreq_get_post_divider_power()` sólo elige `POST_DIV_4` (≥375 MHz) o `POST_DIV_8`.
Con `/4` la salida máxima es `POST_DIV_4_MAX_FREQ = 950000 kHz`. Para pasar de 950 MHz haría falta
cambiar el código del driver (nuevo divisor), no sólo la tabla.

### Por qué el "voltaje" de la CPU es real y no una illusion
La 2ª columna de la tabla `c65Tbl` **no es un voltaje**, es el **código del regulador PMIC** de VPROC:

```
voltaje (10uV) = codigo_PMIC * 625 + 51875
índice  96 -> 1.11875 V   (stock)
índice 107 -> 1.18750 V   (este parche)
índice 109 -> 1.20000 V   (techo de MTK: MAX_VPROC_VOLT 120000, usado por las tablas C65OD/C65X)
```

107 está dentro del rango que MTK ya valida en siliconio (1.2 V), así que no es inventar un valor
fuera de rango, es bajar un escalón respecto al máximo de MTK.

---

## 2. Perfiles

`scripts/set-profile.sh <P0|P1|P2|P3>` los aplica **en el código fuente** (hay que recompilar y reflashear).

| | P0 Stock | P1 Diagnóstico | P2 **Recomendado** | P3 Máximo |
|---|---|---|---|---|
| CPU máx | 2301 MHz | 2301 MHz | **2401 MHz** | 2401 MHz |
| VPROC bin 0 | 96 (1.11875 V) | 107 (1.1875 V) | **107 (1.1875 V)** | 107 (1.1875 V) |
| GPU bin 0 | 900 MHz | 900 MHz | **900 MHz** | 950 MHz |
| Pista VCORE GPU | 80000 (riel bajo) | 95000 (riel alto) | **95000 (riel alto)** | 95000 (riel alto) |
| Throttle CPU (TRIP_1) | 65 °C | 90 °C | **90 °C** | 90 °C |
| CATM / PHPB | 75/65 °C | 90 °C | **90 °C** | 90 °C |
| Riesgo | nulo | bajo | **medio** | alto |

**P2 es el perfil por defecto del parche**: CPU a 2401 MHz con voltaje de MTK, GPU a 900 MHz pero
con el riel VCORE en el escalón alto, y el *throttle* térmico 25 °C más tarde.

Orden recomendado de pruebas: **P2** (si va bien) → **P3** (si quieres rajar la GPU) →
**P1** (si algo se reinicia o hay artifacts: mismo voltaje, sin subir frecuencias).
P0 = volver a stock sin tocar nada.

---

## 3. El DTB del fabricante NO se toca (y por qué no hace falta)

Analicé el `boot.img` real de la partición `boot` (64 MB) y su disposición es:

```
offset 0          cabecera ANDROID!  (kernel_size@8, ramdisk_size@16, page_size@36=2048)
offset 2048       kernel (gzip, 13.866.913 bytes)      <-- lo unico que sustituimos
offset 13.869.056 ramdisk (gzip, 739.540 bytes)
+ padding         bloque MTK de 64 bytes (magic 0x1eabb7d7) + device tree del fabricante
                  (FDT de 127.044 bytes, model "MT6765", compatible "mediatek,MT6765")
```

El DTB de MIUI es una **sección propia del boot.img**, no va pegado al kernel, y la placa
("angelica") viene en la partición `dtbo` como overlay. Por eso:

1. **No hace falta recompilar el DTB**: el driver de cpufreq de este kernel **no** lee las OPP del
   device tree para la frecuencia. La tabla real está en el kernel:
   `policy->cpuinfo.max_freq = cpu_dvfs_get_max_freq(p)` → `p->opp_tbl[0].cpufreq_khz` →
   `CPU_DVFS_FREQ0_L_C65`. Y en `drivers/opp/` no hay ni una referencia a `struct cpufreq_policy`:
   las OPP del DT sólo se usan para el *energy model*. El firmware SCP ejecuta la tabla `c65Tbl`,
   que también está en el kernel.
2. **Sustituir el DTB tocaría la configuración de la placa** (cámara, panel, LEDs...). El plan es
   no tocarlo: `repack-boot.py` deja el DTB del fabricante byte a byte igual y solo cambia el kernel.

El DTB del OEM tiene `opp15 = 2301000000` / `1118750 uV` (igual que la tabla del kernel), así que
además el kernel y el DTB quedan coherentes entre sí.

---

## 4. Compilar: opción rápida (GitHub Actions)

El repo `jujutsu-kernel` trae el workflow **"MIUI OC build (angelica)"**
(`.github/workflows/miui-oc.yml`). Hace todo solo:

1. Aplica el perfil OC (`oc-release/scripts/set-profile.sh`).
2. Baja `SUBLEVEL` a 127 y pone `CONFIG_LOCALVERSION="-perf-g7288046673d5"`.
3. Usa `oc-release/config/device-config.txt` = el `/proc/config.gz` **exacto** del móvil
   (hace falta porque `CONFIG_MODVERSIONS=y` y los CRC de los símbolos dependen de la config).
4. Compila con clang 11.0.1 (el mismo `CONFIG_CLANG_VERSION=110001` del móvil) y sube
   `Image.gz` + `build.log` + `.config` como artefactos.

Para usarlo:

```bash
cd jujutsu-kernel
git add .github/workflows/miui-oc.yml oc-release/
git commit -m "MIUI OC build workflow"
git push origin oc-miui
```

Luego en GitHub → *Actions* → **MIUI OC build (angelica)** → *Run workflow* (perfil `P2`,
config `oem`) → descarga el artefacto `Image.gz-<sha>`.

El workflow **falla si la versión no es exactamente** `4.19.127-perf-g7288046673d5`, porque si no
coincide los módulos de MIUI (wifi, cámara…) no cargan.

### Compilar en local (opcional)

Hace falta clang 11.0.1 + gcc 4.9 (los de las instrucciones del repo) y `make`:

```bash
cd jujutsu-kernel
bash oc-release/scripts/set-profile.sh P2 .
./oc-release/scripts/build-kernel.sh .   # spoof de version + config del movil + make
```

---

## 5. Empaquetar el kernel en el boot.img

`oc-release/backup/boot_stock.img` es el `boot.img` **original** del móvil (extraído de la
partición `boot`; md5 `abfeb19aaa4103f5c64001e9594095e5`).

> Este bootloader **no** soporta `fastboot fetch` ("Device does not support fetch command"), así que
> el `boot.img` original hay que sacarlo de otra forma. El recovery del móvil da adb con root:
>
> ```bash
> adb reboot recovery
> MSYS_NO_PATHCONV=1 adb pull /dev/block/by-name/boot boot_stock.img
> ```

`repack-boot.py` sustituye sólo el kernel y conserva el resto:

```bash
python oc-release/scripts/repack-boot.py --inspect boot_stock.img      # ver la estructura
python oc-release/scripts/repack-boot.py boot_stock.img Image.gz boot_oc.img
```

- Modo normal: el kernel se escribe en su hueco y se rellena con ceros → **la cabecera, el
  ramdisk y el DTB se quedan en el mismo offset byte a byte** (lo más seguro).
- Modo `--shift`: reconstruye la imagen si el kernel nuevo no cabe en el hueco original
  (13.866.913 bytes). El script avisa si hace falta.

---

## 6. Flashear

```bash
bash oc-release/scripts/flash.sh boot_oc.img              # fastboot
bash oc-release/scripts/flash.sh boot_oc.img recovery     # escribe la particion con dd
```

O a mano:

```bash
adb reboot bootloader
fastboot flash boot boot_oc.img
fastboot reboot
```

**Antes de flashear, guarda el boot original** (ya está en `oc-release/backup/boot_stock.img`).

---

## 7. Verificar que todo se aplicó

```bash
bash oc-release/scripts/monitor.sh          # en vivo: freq, volt, temperatura, ventiladores térmicos
```

Valores de referencia (medidos en el móvil, kernel de MIUI sin parche):

| | Stock (MIUI) | Después del parche (P2) |
|---|---|---|
| `gpufreq_opp_dump` [0] | `freq = 900000, volt = 80000` | `freq = 900000, volt = 95000` |
| `gpufreq_var_dump` | `current vcore opp = 0` | `current vcore opp = 0` (riel alto) |
| Riel VCORE (`dvfsrc_dump`) | `Vcore : 800000 uv` | **≥ 800000 uv** (no 650000) |
| `scaling_available_frequencies` | empieza en `2301000` | empieza en `2401000` |
| `uname -a` | `4.19.127-perf-g7288046673d5` | `4.19.127-perf-g7288046673d5` |

Si tras flashear el riel VCORE sigue en 650000 uv, el parche no se aplicó (o el kernel no es el
nuestro).

O a mano:

```bash
# la versión tiene que ser EXACTA o los módulos de MIUI no cargan
adb shell uname -a
#   -> Linux localhost 4.19.127-perf-g7288046673d5 ...

# CPU
adb shell cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies | head -2
#   -> debe empezar por 2401000
adb shell cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq      # -> 2401000
adb shell cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq      # bajo carga

# GPU
adb shell cat /proc/gpufreq/gpufreq_opp_dump
#   -> [0] freq = 900000, volt = 95000
adb shell cat /proc/gpufreq/gpufreq_var_dump | grep vcore
#   -> current vcore opp = 0   (0 = escalón VCORE más alto)

# Riel VCORE real (necesita el nodo dvfsrc)
adb shell cat "/sys/class/regulator/regulator.3/10012000.dvfsrc:dvfsrc-debug-vcore/dvfsrc_dump" | head -2
#   -> Vcore : <ya no 650000>

# Throttle térmico
adb shell cat /sys/class/thermal/thermal_zone*/type | grep mtktscpu
adb shell cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq   # 2401000 mientras no haya throttling
```

Si `scaling_cur_freq` se queda en 2301 o menos bajo carga, el SCP está limitando: el bin 2401 no lo
alcanza el PLL de este lote → quédate en P1.

---

## 8. Rollback

```bash
fastboot flash boot oc-release/backup/boot_stock.img
```

Y en el árbol: `git checkout -- drivers/` o `git apply -R oc-release/mt6765-oc-overvolt-thermal.patch`.

Si el móvil no arranca tras flashear: entra en recovery (`adb reboot recovery`) y
`dd` del original, o `fastboot flash boot oc-release/backup/boot_stock.img`.

---

## 9. Seguridad (léelo, no es opcional)

- El límite de 117 °C (TRIP_0) es el del silicio: si lo alcanzas, el móvil se apaga. Con el cooler
  pegado a la tapa, 90 °C de objetivo están bien, pero **vigila la batería**: si se hincha o el
  móvil se apaga solo, vuelve a P1 y deja descansar.
- 1.1875 V sobre un chip de gama baja es conservative (MTK usa 1.2 V en sus binarios OC), pero cada
  lote de silicio es distinto. Si notas reinicios o artefactos en el juego, baja de perfil.
- La GPU a 900 MHz **con el riel VCORE alto** sube el consumo respecto a stock (stock tenía la GPU
  en el riel bajo por error). Con el cooler, la sesión larga puede calentar más la carcasa que el SoC.
- Este parche **no** sube la CPU más allá de 2401 MHz porque el PLL del L-cluster no da más, ni la
  GPU más allá de 950 MHz porque el divisor del driver no da más. Eso no se puede forzar desde la
  tabla: requiere tocar el driver de clocks (y el firmware SCP), con riesgo real de cuelgue.

---

## 10. Qué hay en esta carpeta

```
mt6765-oc-overvolt-thermal.patch   el parche (5 archivos)
config/device-config.txt           config exacta del kernel de MIUI que corre en el móvil
backup/boot_stock.img              boot.img original del móvil (para empaquetar y para rollback)
backup/kernel_stock.gz             kernel original extraído del boot.img (para probar el empaquetado)
scripts/set-profile.sh             cambia de perfil (P0/P1/P2/P3) en el código
scripts/build-kernel.sh            build local con todo lo necesario para MIUI
scripts/repack-boot.py             mete el kernel nuevo en el boot.img conservando ramdisk y DTB
scripts/flash.sh                   fastboot flash (o escritura desde recovery)
scripts/monitor.sh                 monitor en vivo (temp, freq, volt, throttling)
scripts/perfil-juego.sh            tuning en runtime (governor + GPU fija) — necesita root
```

Nota: el parche lleva comentarios explicativos dentro del código; `set-profile.sh` sólo reescribe
los valores. Aplicado sobre un árbol limpio, los **valores** quedan idénticos al parche (lo que
compila es lo mismo), pero el kernel resultante no lleva esos comentarios.
