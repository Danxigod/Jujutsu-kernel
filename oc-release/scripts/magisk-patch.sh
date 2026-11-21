#!/usr/bin/env bash
# magisk-patch.sh - parchea el boot_oc.img con Magisk usando el propio script oficial
#                   (assets/boot_patch.sh del APK) ejecutado en el movil por adb.
#
#   ./magisk-patch.sh            -> extrae los binarios, los sube al movil, parchea y verifica
#   ./magisk-patch.sh prepare    -> solo deja los binarios preparados (sin movil)
#
# No hace falta root ni la app de Magisk: boot_patch.sh solo modifica el fichero.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REL="$ROOT/oc-release"
IMG="${IMG:-$REL/boot_oc_final.img}"
APK="${APK:-$REL/Magisk-v31.1.apk}"
BINDIR="$REL/magisk-bin"
OUT="${OUT:-$REL/magisk_patched.img}"
REMOTE="/data/local/tmp/magisk"

if [ -x "$ROOT/tools/platform-tools/adb" ]; then
	ADB="$ROOT/tools/platform-tools/adb"
else
	ADB="$(command -v adb || true)"
fi
export MSYS_NO_PATHCONV=1
PY="$(command -v python3 || command -v python)"

# Python es nativo de Windows: necesita rutas estilo C:\..., no las de Git Bash
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }

# ---------------------------------------------------------- 1) extraer del APK
echo "== Extrayendo los binarios de Magisk del APK"
mkdir -p "$BINDIR"
"$PY" - "$(winpath "$APK")" "$(winpath "$BINDIR")" <<'PY'
import zipfile, sys, os, shutil
apk, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(apk)
mapping = {
    'lib/arm64-v8a/libmagiskboot.so': 'magiskboot',
    'lib/arm64-v8a/libmagiskinit.so': 'magiskinit',
    'lib/arm64-v8a/libmagisk.so': 'magisk',
    'lib/arm64-v8a/libinit-ld.so': 'init-ld',
    'lib/arm64-v8a/libbusybox.so': 'busybox',
    'assets/boot_patch.sh': 'boot_patch.sh',
    'assets/util_functions.sh': 'util_functions.sh',
}
for src, dst in mapping.items():
    with z.open(src) as f, open(os.path.join(out, dst), 'wb') as g:
        shutil.copyfileobj(f, g)
    print('  %-20s <- %s' % (dst, src))
PY
chmod 755 "$BINDIR"/* 2>/dev/null || true

if [ "${1:-}" = "prepare" ]; then
	echo "== Listo. Binarios en $BINDIR"
	exit 0
fi

[ -n "$ADB" ] || { echo "falta adb" >&2; exit 1; }
[ -f "$IMG" ] || { echo "No existe $IMG" >&2; exit 1; }
"$ADB" get-state 2>/dev/null | grep -q device || { echo "El movil no esta conectado por adb" >&2; exit 1; }

# ---------------------------------------------------------- 2) subir y parchar
echo
echo "== Subiendo al movil"
"$ADB" shell "rm -rf $REMOTE && mkdir -p $REMOTE"
"$ADB" push "$(winpath "$BINDIR")/." "$REMOTE/" >/dev/null
"$ADB" push "$(winpath "$IMG")" "$REMOTE/boot_oc.img" >/dev/null
"$ADB" shell "chmod -R 755 $REMOTE"

echo "== Parcheando (boot_patch.sh oficial)"
"$ADB" shell "cd $REMOTE && sh boot_patch.sh boot_oc.img"

echo
echo "== Descargando el resultado"
# magiskboot repack escribe en new-boot.img (no toca el original)
"$ADB" pull "$REMOTE/new-boot.img" "$OUT" >/dev/null
ls -l "$OUT"

# ---------------------------------------------------------- 3) verificar
echo
echo "== Verificacion"
"$PY" - "$(winpath "$OUT")" "$(winpath "$IMG")" "$(winpath "$REL/backup/boot_stock.img")" <<'PY'
import struct, sys, hashlib, gzip, io

patched = open(sys.argv[1], 'rb').read()
oc      = open(sys.argv[2], 'rb').read()
stock   = open(sys.argv[3], 'rb').read()

FDT_MAGIC = b'\xd0\x0d\xfe\xed'

def layout(b):
    ksz = struct.unpack_from('<I', b, 8)[0]
    psz = struct.unpack_from('<I', b, 36)[0]
    rsz = struct.unpack_from('<I', b, 16)[0]
    koff = psz
    roff = (koff + ksz + psz - 1) // psz * psz
    return dict(page=psz, ksz=ksz, rsz=rsz, koff=koff,
                kernel=b[koff:koff + ksz], ramdisk=b[roff:roff + rsz])

def fdt(b):
    i = b.find(FDT_MAGIC)
    if i < 0:
        return None
    return b[i:i + struct.unpack_from('>I', b, i + 4)[0]]

def gunzip(b):
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=io.BytesIO(b)) as g:
        out.write(g.read())
    return out.getvalue()

p, o, s = layout(patched), layout(oc), layout(stock)
ok = True
def check(name, cond):
    global ok
    ok = ok and bool(cond)
    print(('  OK    ' if cond else '  FALLO ') + name)

print('pagina %d | kernel %d bytes | ramdisk %d bytes' % (p['page'], p['ksz'], p['rsz']))

# el kernel: magiskboot lo recomprime, asi que se compara DESCOMPRIMIDO
try:
    kp, ko = gunzip(p['kernel']), gunzip(o['kernel'])
    check('el kernel OC sigue dentro (%d bytes descomprimidos)' % len(kp),
          kp == ko and len(kp) > 0)
    check('el kernel lleva la version de MIUI',
          b'4.19.127-perf-g7288046673d5' in kp)
except Exception as e:
    check('el kernel se descomprime (%s)' % e, False)

check('el ramdisk ha sido sustituido por el de Magisk', p['ramdisk'] != o['ramdisk'])
check('el ramdisk nuevo es un gzip valido', p['ramdisk'][:2] == b'\x1f\x8b')

fd, fs = fdt(patched), fdt(stock)
check('el DTB del fabricante sigue intacto (%s bytes)' % (len(fs) if fs else '?'),
      fd is not None and fs is not None and fd == fs)

print('md5 imagen parcheada:', hashlib.md5(patched).hexdigest())
print('md5 kernel OC       :', hashlib.md5(ko).hexdigest())
print()
print('RESULTADO:', 'todo correcto, se puede flashear' if ok else 'REVISAR antes de flashear')
sys.exit(0 if ok else 1)
PY

echo
echo "Instalar despues la app (opcional, para el manager):"
echo "   adb install $APK"
echo
echo "Siguiente paso (esperando tu confirmacion):"
echo "   fastboot flash boot $OUT"
