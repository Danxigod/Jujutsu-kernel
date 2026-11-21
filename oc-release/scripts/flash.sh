#!/usr/bin/env bash
# flash.sh - flashea el boot.img con el kernel nuevo
#
#   ./flash.sh [imagen]            -> fastboot (modo normal)
#   ./flash.sh [imagen] recovery   -> escribe la particion boot desde el recovery
#
# El recovery del movil da adb con root (uid=0), asi que el modo recovery sirve
# como alternativa si fastboot se queda colgado.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -x "$ROOT/tools/platform-tools/adb" ]; then
	ADB="$ROOT/tools/platform-tools/adb"
	FASTBOOT="$ROOT/tools/platform-tools/fastboot"
else
	ADB="$(command -v adb || true)"
	FASTBOOT="$(command -v fastboot || true)"
fi

IMG="${1:-boot_oc.img}"
MODE="${2:-fastboot}"

if [ ! -f "$IMG" ]; then
	echo "No encuentro la imagen: $IMG" >&2
	exit 1
fi

case "$MODE" in
fastboot)
	echo "== Modo fastboot =="
	"$ADB" reboot bootloader
	for _ in $(seq 1 30); do
		sleep 2
		if "$FASTBOOT" devices | grep -q fastboot; then break; fi
	done
	"$FASTBOOT" devices
	echo "Flasheando $IMG..."
	"$FASTBOOT" flash boot "$IMG"
	"$FASTBOOT" reboot
	;;
recovery)
	echo "== Modo recovery (escribe /dev/block/by-name/boot) =="
	"$ADB" reboot recovery
	for _ in $(seq 1 30); do
		sleep 2
		if [ "$("$ADB" get-state 2>/dev/null || true)" = "device" ]; then break; fi
	done
	"$ADB" push "$IMG" /data/local/tmp/boot_oc.img
	"$ADB" shell "dd if=/data/local/tmp/boot_oc.img of=/dev/block/by-name/boot bs=4096"
	"$ADB" shell "sync"
	"$ADB" reboot
	;;
*)
	echo "Modo desconocido: $MODE (usa fastboot o recovery)" >&2
	exit 1
	;;
esac

echo "Hecho. Al arrancar:"
echo "  adb shell uname -a            # debe decir 4.19.127-perf-g7288046673d5"
echo "  adb shell cat /proc/gpufreq/gpufreq_opp_dump"
