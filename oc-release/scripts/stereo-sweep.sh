#!/usr/bin/env bash
# stereo-sweep.sh - recorre las combinaciones de mux del auricular y del
# altavoz para buscar la que separa los canales (uno arriba y otro abajo).
#
# Pone una combinacion, espera a que se escuchando y pide confirmacion.
# Con cada combinacion sirve tener listo un archivo de audio con un canal
# distinto en cada lado (por ejemplo "prueba-estereo.wav").
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="${ADB:-$(command -v adb || echo "$HOME/../tools/platform-tools/adb.exe")}"
PROC=/proc/oc_stereo
GAIN="${GAIN:-12}"
LOLGAIN="${LOLGAIN:--1}"

sh() { "$ADB" shell "$@"; }

echo "== estado inicial =="
sh "cat $PROC"

for hs in 0 1 2 3; do
	for lo in 0 1 2 3; do
		echo
		echo "== auricular mux=$hs  altavoz mux=$lo  (gain=$GAIN lolgain=$LOLGAIN) =="
		sh "echo mux=$hs > $PROC"
		sh "echo lolmux=$lo > $PROC"
		sh "echo gain=$GAIN > $PROC"
		sh "echo lolgain=$LOLGAIN > $PROC"
		sh "cat $PROC"
		printf "  suenan arriba y abajo separados? [s/n] "
		read -r ans
		if [ "$ans" = "s" ] || [ "$ans" = "S" ]; then
			echo "COMBINACION BUENA: mux=$hs lolmux=$lo gain=$GAIN lolgain=$LOLGAIN"
			exit 0
		fi
	done
done

echo "Ninguna combinacion ha servido tal cual: se puede probar cambiando gain/lolgain"
