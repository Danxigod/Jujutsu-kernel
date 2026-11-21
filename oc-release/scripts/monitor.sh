#!/usr/bin/env bash
# monitor.sh - monitor en vivo del movil (frecuencias, tension, temperatura, throttling)
# Uso: ./monitor.sh [intervalo_segundos]
set -uo pipefail

INTERVAL="${1:-2}"
ADB="${ADB:-adb}"

command -v "$ADB" >/dev/null 2>&1 || { echo "falta adb en el PATH (o define ADB=/ruta/adb)" >&2; exit 1; }

REMOTE='
Z=/sys/class/thermal
cpu=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
cmax=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null)
ll=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null)
gpu=$(cat /sys/kernel/ged/hal/current_freqency 2>/dev/null)
if [ -z "$gpu" ]; then
  g=$(grep -m1 g_cur_opp_freq /proc/gpufreq/gpufreq_var_dump 2>/dev/null)
  gpu=${g#*= }; gpu=${gpu%%,*}
fi
ts=""
for z in $Z/thermal_zone*; do
  t=$(cat $z/type 2>/dev/null)
  [ "$t" = "mtktscpu" ] && ts=$(cat $z/temp 2>/dev/null)
done
v=$(cat "/sys/class/regulator/regulator.3/10012000.dvfsrc:dvfsrc-debug-vcore/dvfsrc_dump" 2>/dev/null | head -1)
vcore=${v#*:}; vcore=${vcore# }; vcore=${vcore%% *}
th=""
for c in $Z/cooling_device*; do
  s=$(cat $c/cur_state 2>/dev/null)
  case "$s" in ""|*[!0-9]*) continue;; esac
  if [ "$s" -gt 0 ] && [ "$s" -le 100 ]; then th="$th$(cat $c/type 2>/dev/null)=$s,"; fi
done
echo "S $cpu $cmax $ll $gpu $ts $vcore $th"
'

printf '\033[1m%-9s %-9s %-9s %-9s %-9s %-8s %-8s %s\033[0m\n' \
	"HORA" "CPUbig" "CPUMax" "CPULil" "GPU" "mtscpu" "VCORE" "THROTTLE"
printf '%.0s-' {1..92}; echo

while true; do
	OUT="$("$ADB" shell "$REMOTE" 2>/dev/null | tr -d '\r' | grep '^S ' | head -1)"

	if [ -z "$OUT" ]; then
		printf '%-9s %s\n' "$(date +%H:%M:%S)" "(sin respuesta de adb)"
		sleep "$INTERVAL"
		continue
	fi

	read -r _ cpu cmax ll gpu ts vcore th <<<"$OUT"

	GPUF=$(awk -v g="${gpu:-0}" 'BEGIN{printf "%.0fMHz", g/1000}')
	TSF=$(awk -v t="${ts:-0}" 'BEGIN{printf "%.1fC", t/1000}')
	VCF=$(awk -v v="${vcore:-0}" 'BEGIN{printf "%.0fmV", v/1000}')
	TH="${th%,}"

	LINE=$(printf '%-9s %-9s %-9s %-9s %-9s %-8s %-8s %s' \
		"$(date +%H:%M:%S)" "${cpu:-?}" "${cmax:-?}" "${ll:-?}" "$GPUF" "${TSF}" "${VCF}" "${TH:--}")

	if [ -n "$TH" ]; then
		printf '\033[33m%s\033[0m\n' "$LINE"
	else
		printf '%s\n' "$LINE"
	fi

	sleep "$INTERVAL"
done
