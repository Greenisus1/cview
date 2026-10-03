#!/bin/sh
# Live Pi monitor. Refreshes every 2 seconds. Stop with Ctrl+C.
# Shows RAM, swap, CPU use and load, temperature, throttle state, and service up or down.
G=$(printf '\033[32m'); Rd=$(printf '\033[31m'); Y=$(printf '\033[33m'); B=$(printf '\033[1m'); N=$(printf '\033[0m')
trap 'printf "\033[?25h\n"; exit 0' INT TERM
printf '\033[?25l'
cpu_line() { head -n 1 /proc/stat; }
prev=$(cpu_line)
while true; do
  cur=$(cpu_line)
  CPU=$(printf '%s\n%s\n' "$prev" "$cur" | awk 'NR==1{for(i=2;i<=NF;i++)a+=$i;ai=$5+$6} NR==2{for(i=2;i<=NF;i++)b+=$i;bi=$5+$6} END{d=b-a; if(d>0)printf "%.0f", (d-(bi-ai))*100/d; else print 0}')
  prev=$cur
  MEM=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} /SwapTotal/{st=$2} /SwapFree/{sf=$2} END{printf "%d %d %d %d", (t-a)/1024, t/1024, (st-sf)/1024, st/1024}' /proc/meminfo)
  set -- $MEM
  MU=$1; MT=$2; SU=$3; ST=$4
  LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
  CORES=$(nproc 2>/dev/null || echo 1)
  T=""
  if command -v vcgencmd >/dev/null 2>&1; then
    T=$(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//')
  fi
  if [ -z "$T" ] && [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    T=$(awk '{printf "%.1f'"'"'C", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
  fi
  TN=$(echo "$T" | sed 's/[^0-9.].*//')
  TC=$G
  [ -n "$TN" ] && [ "${TN%.*}" -ge 70 ] 2>/dev/null && TC=$Y
  [ -n "$TN" ] && [ "${TN%.*}" -ge 80 ] 2>/dev/null && TC=$Rd
  THR="not available (no vcgencmd)"
  if command -v vcgencmd >/dev/null 2>&1; then
    H=$(vcgencmd get_throttled 2>/dev/null | sed 's/throttled=//')
    if [ -n "$H" ]; then
      V=$(( H ))
      if [ "$V" -eq 0 ]; then THR="${G}OK, never throttled${N}"
      else
        THR=""
        [ $(( V & 1 )) -ne 0 ] && THR="$THR ${Rd}under-voltage NOW${N}"
        [ $(( V & 2 )) -ne 0 ] && THR="$THR ${Rd}speed capped NOW${N}"
        [ $(( V & 4 )) -ne 0 ] && THR="$THR ${Rd}throttled NOW${N}"
        [ $(( V & 8 )) -ne 0 ] && THR="$THR ${Y}temp limit NOW${N}"
        [ $(( V & 0xF0000 )) -ne 0 ] && THR="$THR ${Y}(happened since boot)${N}"
      fi
    fi
  fi
  printf '\033[H\033[2J'
  printf '%sPi monitor%s   %s   (Ctrl+C to stop)\n\n' "$B" "$N" "$(date +%H:%M:%S)"
  printf 'CPU use   %s%%   load %s  (%s cores)\n' "$CPU" "$LOAD" "$CORES"
  printf 'CPU temp  %s%s%s\n' "$TC" "${T:-n/a}" "$N"
  printf 'Throttle  %s\n' "$THR"
  printf 'RAM       %s / %s MB used\n' "$MU" "$MT"
  printf 'Swap      %s / %s MB used\n' "$SU" "$ST"
  printf 'GPU       no useful GPU stat on a Pi, see temp and throttle\n\n'
  printf '%sServices%s\n' "$B" "$N"
  for pair in cbtunnel:Tunnel crunchbyte:Crunchbyte-site shortsite:Short-link-site ollama:Ollama; do
    U=${pair%%:*}; L=${pair##*:}
    S=$(systemctl is-active $U 2>/dev/null)
    if [ "$S" = "active" ]; then printf '  %-18s %sUP%s\n' "$L" "$G" "$N"; else printf '  %-18s %sDOWN%s (%s)\n' "$L" "$Rd" "$N" "${S:-unknown}"; fi
  done
  if command -v ollama >/dev/null 2>&1; then
    M=$(ollama ps 2>/dev/null | awk 'NR>1{print $1}' | head -n 1)
    printf '  %-18s %s\n' "Model loaded" "${M:-none right now}"
  fi
  sleep 2
done
