#!/usr/bin/env bash
# set-profile.sh - deja el arbol del kernel en el perfil pedido
# Uso: ./set-profile.sh <P0|P1|P2|P3> [ruta/al/arbol]
set -euo pipefail

PROFILE="${1:-}"
TREE="${2:-}"

if [ -z "$PROFILE" ]; then
	echo "Uso: $0 <P0|P1|P2|P3> [ruta/al/arbol]" >&2
	exit 1
fi

if [ -z "$TREE" ]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	TREE="$(cd "$SCRIPT_DIR/../.." && pwd)/jujutsu-kernel"
fi

if [ ! -f "$TREE/Makefile" ]; then
	echo "No encuentro el arbol del kernel en: $TREE" >&2
	exit 1
fi

FILES=(
	"drivers/gpu/mediatek/gpufreq/mt6765/mtk_gpufreq_core.h"
	"drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6765/mtk_cpufreq_opp_table.h"
	"drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6765/mtk_cpufreq_opp_pv_table.h"
	"drivers/misc/mediatek/thermal/mt6765/inc/tzcpu_initcfg.h"
	"drivers/misc/mediatek/thermal/mt6765/inc/clatm_initcfg.h"
)

case "$PROFILE" in
P0)
	echo "== P0: stock CAF (deshace los cambios en los 5 archivos) =="
	git -C "$TREE" checkout -- "${FILES[@]}"
	exit 0
	;;
P1) CPU_FREQ=2301000; CPU_VPROC=107; CPU_VOLT=118750; GPU_F0=900000; GPU_F1=780000; GPU_F2=600000
    GPU_H0=95000;   GPU_H1=85000;    GPU_H2=70000
    T1=90000; T2=89000; T3=88000; T4=87000; T5=85000; T6=80000; T7=75000; T8=70000; T9=65000
    CATM=90000; CLCTM=95000 ;;
P2) CPU_FREQ=2401000; CPU_VPROC=107; CPU_VOLT=118750; GPU_F0=900000; GPU_F1=780000; GPU_F2=600000
    GPU_H0=95000;   GPU_H1=85000;    GPU_H2=70000
    T1=90000; T2=89000; T3=88000; T4=87000; T5=85000; T6=80000; T7=75000; T8=70000; T9=65000
    CATM=90000; CLCTM=95000 ;;
P3) CPU_FREQ=2401000; CPU_VPROC=107; CPU_VOLT=118750; GPU_F0=950000; GPU_F1=780000; GPU_F2=600000
    GPU_H0=95000;   GPU_H1=85000;    GPU_H2=70000
    T1=90000; T2=89000; T3=88000; T4=87000; T5=85000; T6=80000; T7=75000; T8=70000; T9=65000
    CATM=90000; CLCTM=95000 ;;
*)
	echo "Perfil desconocido: $PROFILE (usa P0, P1, P2 o P3)" >&2
	exit 1
	;;
esac

CPU_FREQ_MHZ=$((CPU_FREQ / 1000))

echo "== Perfil $PROFILE =="
echo "   CPU $CPU_FREQ_MHZ MHz | VPROC code $CPU_VPROC ($CPU_VOLT x10uV) | GPU $GPU_F0/$GPU_F1/$GPU_F2 kHz"
echo "   Pista VCORE GPU $GPU_H0/$GPU_H1/$GPU_H2 | Throttle TRIP_1 $T1 | CATM $CATM | CLCTM $CLCTM"

GPU_H="$TREE/drivers/gpu/mediatek/gpufreq/mt6765/mtk_gpufreq_core.h"
OPP="$TREE/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6765/mtk_cpufreq_opp_table.h"
PV="$TREE/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6765/mtk_cpufreq_opp_pv_table.h"
TZ="$TREE/drivers/misc/mediatek/thermal/mt6765/inc/tzcpu_initcfg.h"
CATM_F="$TREE/drivers/misc/mediatek/thermal/mt6765/inc/clatm_initcfg.h"

# ---- GPU (segmento 3) ----
sed -i \
	-e "s/^#define SEG3_GPU_DVFS_FREQ0.*$/#define SEG3_GPU_DVFS_FREQ0\t\t\t\\($GPU_F0\\)\t\/* KHz *\//" \
	-e "s/^#define SEG3_GPU_DVFS_FREQ1.*$/#define SEG3_GPU_DVFS_FREQ1\t\t\t\\($GPU_F1\\)\t\/* KHz *\//" \
	-e "s/^#define SEG3_GPU_DVFS_FREQ2.*$/#define SEG3_GPU_DVFS_FREQ2\t\t\t\\($GPU_F2\\)\t\/* KHz *\//" \
	-e "s/^#define SEG3_GPU_DVFS_VOLT0.*$/#define SEG3_GPU_DVFS_VOLT0\t\t\t\\($GPU_H0\\)\t\t\/* mV x 100 *\//" \
	-e "s/^#define SEG3_GPU_DVFS_VOLT1.*$/#define SEG3_GPU_DVFS_VOLT1\t\t\t\\($GPU_H1\\)\t\t\/* mV x 100 *\//" \
	-e "s/^#define SEG3_GPU_DVFS_VOLT2.*$/#define SEG3_GPU_DVFS_VOLT2\t\t\t\\($GPU_H2\\)\t\t\/* mV x 100 *\//" \
	"$GPU_H"

# ---- CPU: tabla OPP ----
sed -i \
	-e "s/^#define CPU_DVFS_FREQ0_L_C65[[:space:]]\+[0-9]\+/#define CPU_DVFS_FREQ0_L_C65    $CPU_FREQ/" \
	-e "s/^#define CPU_DVFS_VOLT0_VPROC_L_C65[[:space:]]\+[0-9]\+/#define CPU_DVFS_VOLT0_VPROC_L_C65    $CPU_VOLT/" \
	"$OPP"

# ---- CPU: tabla SRAM (primera fila de c65Tbl) ----
awk -v FREQ="$CPU_FREQ_MHZ" -v VPROC="$CPU_VPROC" '
/^static unsigned int c65Tbl\[/ { inblock = 1; first = 1 }
inblock && first && /^[[:space:]]*\{[[:space:]]*[0-9]+,[[:space:]]*[0-9]+,[[:space:]]*[0-9]+,[[:space:]]*[0-9]+[[:space:]]*\},/ {
	match($0, /^[[:space:]]*/)
	indent = substr($0, RSTART, RLENGTH)
	printf "%s{ %s, %s, 1, 1 },\t/* L */\n", indent, FREQ, VPROC
	first = 0
	next
}
/^\};/ { inblock = 0 }
{ print }
' "$PV" > "$PV.tmp" && mv "$PV.tmp" "$PV"

# ---- Thermal: trips de CPU ----
sed -i \
	-e "s/^#define TZCPU_INITCFG_TRIP_1_TEMP.*$/#define TZCPU_INITCFG_TRIP_1_TEMP\t\t($T1)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_2_TEMP.*$/#define TZCPU_INITCFG_TRIP_2_TEMP\t\t($T2)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_3_TEMP.*$/#define TZCPU_INITCFG_TRIP_3_TEMP\t\t($T3)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_4_TEMP.*$/#define TZCPU_INITCFG_TRIP_4_TEMP\t\t($T4)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_5_TEMP.*$/#define TZCPU_INITCFG_TRIP_5_TEMP\t\t($T5)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_6_TEMP.*$/#define TZCPU_INITCFG_TRIP_6_TEMP\t\t($T6)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_7_TEMP.*$/#define TZCPU_INITCFG_TRIP_7_TEMP\t\t($T7)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_8_TEMP.*$/#define TZCPU_INITCFG_TRIP_8_TEMP\t\t($T8)/" \
	-e "s/^#define TZCPU_INITCFG_TRIP_9_TEMP.*$/#define TZCPU_INITCFG_TRIP_9_TEMP\t\t($T9)/" \
	"$TZ"

# ---- Thermal: presupuesto CATM / PHPB ----
sed -i \
	-e "s/^#define CLATM_INIT_CFG_0_TARGET_TJ.*$/#define CLATM_INIT_CFG_0_TARGET_TJ\t\t($CATM)/" \
	-e "s/^#define CLATM_INIT_CFG_1_TARGET_TJ.*$/#define CLATM_INIT_CFG_1_TARGET_TJ\t\t($CATM)/" \
	-e "s/^#define CLATM_INIT_CFG_2_TARGET_TJ.*$/#define CLATM_INIT_CFG_2_TARGET_TJ\t\t($CATM)/" \
	-e "s/^#define CLCTM_TARGET_TJ.*$/#define CLCTM_TARGET_TJ\t\t\t\t($CLCTM)/" \
	"$CATM_F"

echo "Listo. Revisa con: git -C \"$TREE\" diff --stat"
