#!/usr/bin/env bash
# build-kernel.sh - compila el kernel con TODAS las cosas que necesita MIUI
# Uso: ./build-kernel.sh [ruta/al/arbol] [--hybrid]
#   --hybrid  fuerza CONFIG_HYBRID_CPU_DVFS=y (la tabla SRAM manda en vez de la tabla OPP).
#             No es necesario: el parche actualiza las dos tablas.
set -euo pipefail

TREE="${1:-}"
HYBRID=0
for a in "$@"; do
	[ "$a" = "--hybrid" ] && HYBRID=1
done

if [ -z "$TREE" ]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	TREE="$(cd "$SCRIPT_DIR/../.." && pwd)/jujutsu-kernel"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/../config/device-config.txt"

[ -f "$TREE/Makefile" ] || { echo "Arbol de kernel no valido: $TREE" >&2; exit 1; }
[ -f "$CONFIG_SRC" ] || { echo "Falta la config del movil: $CONFIG_SRC" >&2; exit 1; }

# ---------------------------------------------------------------- toolchain
if ! command -v clang >/dev/null 2>&1; then
	cat >&2 <<'EOF'
clang no esta en el PATH. Necesitas clang 11.0.1 (crdroid r428724) y gcc 4.9 para arm32:

  git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r428724.git /tmp/clang
  git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git /tmp/gcc-aarch64
  git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git /tmp/gcc-arm
  export PATH="/tmp/clang/bin:/tmp/gcc-aarch64/bin:/tmp/gcc-arm/bin:$PATH"
EOF
	exit 1
fi

CLANG_VER="$(clang --version | head -1)"
echo "== Toolchain: $CLANG_VER"
case "$CLANG_VER" in
*11.0.1*) ;;
*) echo "AVISO: el kernel de MIUI se compilo con clang 11.0.1 (CONFIG_CLANG_VERSION=110001)." ;;
esac

# --------------------------------------------------- 1) espiar la version
# Los modulos de /vendor/lib/modules exigen vermagic 4.19.127-perf-g7288046673d5
if grep -q '^SUBLEVEL = 127$' "$TREE/Makefile"; then
	echo "== Version del kernel ya espiada (4.19.127)"
else
	cp "$TREE/Makefile" "$TREE/Makefile.orig-version"
	sed -i -E 's/^SUBLEVEL = [0-9]+$/SUBLEVEL = 127/' "$TREE/Makefile"
	echo "== Version espiada a 4.19.127 (respaldo en Makefile.orig-version)"
fi

# --------------------------------------------------- 2) config del movil
mkdir -p "$TREE/out"
cp "$CONFIG_SRC" "$TREE/.config"
cp "$CONFIG_SRC" "$TREE/out/.config"
cd "$TREE"

./scripts/config --file out/.config --set-str LOCALVERSION "-perf-g7288046673d5"
./scripts/config --file out/.config --disable LOCALVERSION_AUTO
if [ "$HYBRID" = "1" ]; then
	./scripts/config --file out/.config --enable HYBRID_CPU_DVFS
	echo "== CONFIG_HYBRID_CPU_DVFS=y (tabla SRAM)"
else
	echo "== CONFIG_HYBRID_CPU_DVFS sigue como en la config de MIUI (tabla OPP)"
fi

make O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-androideabi- \
	olddefconfig >/dev/null

echo "== Comprobaciones de la config"
for opt in LOCALVERSION LOCALVERSION_AUTO MODVERSIONS MODULE_SIG TRIM_UNUSED_KSYMS CLANG_VERSION; do
	printf '   %-22s %s\n' "$opt" "$(grep -E "^(CONFIG_$opt=|# CONFIG_$opt )" out/.config || echo '(no esta)')"
done

# kernelrelease: make mete sus mensajes en stdout, hay que filtrarlos
RELEASE="$(make -s O=out ARCH=arm64 kernelrelease 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | tail -1)"
echo "== kernelrelease = $RELEASE"
if [ "$RELEASE" != "4.19.127-perf-g7288046673d5" ]; then
	echo "AVISO: la version no es la de MIUI, los modulos de /vendor no cargaran" >&2
fi

# --------------------------------------------------- 3) compilar
export ARCH=arm64
export CROSS_COMPILE="aarch64-linux-android-"
export CROSS_COMPILE_ARM32="arm-linux-androideabi-"
export CC=clang
export CLANG_TRIPLE="aarch64-linux-gnu-"

make -j"$(nproc)" O=out ARCH=arm64 \
	CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE=aarch64-linux-android- \
	CROSS_COMPILE_ARM32=arm-linux-androideabi- \
	Image.gz 2>&1 | tail -30

if [ ! -f "$TREE/out/arch/arm64/boot/Image.gz" ]; then
	echo "== Image.gz no habilitado: se compila Image y se comprime"
	make -j"$(nproc)" O=out ARCH=arm64 \
		CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
		CROSS_COMPILE=aarch64-linux-android- \
		CROSS_COMPILE_ARM32=arm-linux-androideabi- \
		Image 2>&1 | tail -30
	gzip -9 -c "$TREE/out/arch/arm64/boot/Image" > "$TREE/out/arch/arm64/boot/Image.gz"
fi

KERNEL="$TREE/out/arch/arm64/boot/Image.gz"

cat <<EOF

== Listo
   Kernel : $KERNEL

Siguiente paso:
   python "$SCRIPT_DIR/repack-boot.py" <boot_stock.img> "$KERNEL" boot_oc.img
   bash "$SCRIPT_DIR/flash.sh" boot_oc.img
EOF
