#!/usr/bin/env bash
# play.sh - deja sonando el archivo de prueba de forma fiable y comprueba
# que el codec really esta salidas activas (spk_on=1 en /proc/oc_stereo).
#
#   ./play.sh            -> arranca la reproduccion y verifica
#   ./play.sh check      -> solo verifica
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="${ADB:-$(command -v adb || echo "$HOME/../tools/platform-tools/adb.exe")}"
FILE="${FILE:-/sdcard/Music/prueba-estereo.wav}"
PROC=/proc/oc_stereo

sh() { "$ADB" shell "$@"; }

state() { sh "cat $PROC" | tr -d '\r' | head -1; }

if [ "${1:-start}" != "check" ]; then
	sh "am start -a android.intent.action.VIEW -d file://$FILE -t audio/wav -p com.miui.player" >/dev/null 2>&1
	sleep 3
	sh "input keyevent 4" >/dev/null 2>&1
	sleep 1
	sh "cmd media_session dispatch play" >/dev/null 2>&1
fi

for i in 1 2 3 4 5 6 7 8; do
	sleep 2
	s="$(state)"
	case "$s" in
	*"spk_on=1"*)
		echo "sonando: $s"
		exit 0
		;;
	esac
	sh "cmd media_session dispatch play" >/dev/null 2>&1
done

echo "no suena: $(state)"
exit 1
