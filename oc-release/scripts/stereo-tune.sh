#!/usr/bin/env bash
# stereo-tune.sh - ajusta la salida dual del codec MT6357 (auricular + altavoz)
#
#   ./stereo-tune.sh                    muestra el estado actual
#   ./stereo-tune.sh mux=1 lolmux=3     aplica los ajustes y vuelve a mostrar
#
# Comandos disponibles en /proc/oc_stereo:
#   mux=0..3      mux de entrada del auricular (AUDHSMUXINPUTSEL)
#   lolmux=0..3   mux de entrada del altavoz (AUDLOLMUXINPUTSEL)
#   gain=0..18    ganancia del auricular (18 = -40 dB)
#   lolgain=-1..18 ganancia del altavoz (-1 = la que pone el HAL)
#   on / off      activa o desactiva la salida dual
#   force         enciende el auricular ahora mismo
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="${ADB:-$(command -v adb || echo "$HOME/../tools/platform-tools/adb.exe")}"
PROC=/proc/oc_stereo

sh() { "$ADB" shell "$@"; }

if [ "$#" -eq 0 ]; then
	sh "cat $PROC"
	exit $?
fi

for arg in "$@"; do
	case "$arg" in
	mux=*|lolmux=*|gain=*|lolgain=*|on|off|force) ;;
	*)
		echo "comando no valido: $arg" >&2
		exit 1
		;;
	esac
done

for arg in "$@"; do
	out="$(sh "echo $arg > $PROC 2>&1")"
	if [ -n "$out" ]; then
		echo "!! $arg -> $out"
	fi
done

sh "cat $PROC"
