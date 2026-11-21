#!/usr/bin/env bash
# stereo-ab.sh - prueba rapida del auricular: aplica un ajuste, muestra el
# estado del codec y deja sonando el fichero de prueba para comparar a ojo.
#
#   ./stereo-ab.sh                 -> estado actual + sonido
#   ./stereo-ab.sh cmfb=0          -> apaga el CMFB del auricular y reproduce
#   ./stereo-ab.sh hsbias=3        -> sube el bias del auricular y reproduce
#   ./stereo-ab.sh "reg=19a 93"    -> escritura libre de un registro
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="${ADB:-$(command -v adb || echo "$HOME/../tools/platform-tools/adb.exe")}"
PROC=/proc/oc_stereo

sh() { "$ADB" shell "$@"; }

if [ "$#" -gt 0 ]; then
	for arg in "$@"; do
		out="$(sh "echo $arg > $PROC 2>&1")"
		if [ -n "$out" ]; then
			echo "!! $arg -> $out"
		fi
	done
fi

echo "== estado =="
sh "cat $PROC" | tr -d '\r'

echo
echo "== sonando =="
bash "$HERE/play.sh"
