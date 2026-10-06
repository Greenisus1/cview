#!/bin/bash
# ROAD DODGE 2 - Keys: a/d or arrows steer, w or up = speed up, q quits.
boost=0; W=21; H=18; lives=3; score=0; px=$((W/2)); tick=0; speed=0.12
declare -a rows
for ((i=0;i<H;i++)); do rows[i]=""; done
cleanup(){ tput cnorm; tput rmcup 2>/dev/null; stty sane; }
trap cleanup EXIT
tput smcup 2>/dev/null; tput civis; clear
newrow(){
  local r="" i
  for ((i=0;i<W;i++)); do r+=" "; done
  if (( RANDOM%3==0 )); then
    local n=$((1+RANDOM%2)) k p
    for ((k=0;k<n;k++)); do p=$((RANDOM%W)); r="${r:0:p}#${r:p+1}"; done
  fi
  echo "$r"
}
blank=""; for ((i=0;i<W;i++)); do blank+=" "; done
for ((i=0;i<H;i++)); do rows[i]="$blank"; done
hit=0
while (( lives>0 )); do
  key=""
  eff=$speed; ((boost>0)) && { eff=$(awk -v s=$speed "BEGIN{print s/2}"); ((boost--)); }
  read -rsn1 -t $eff key
  if [[ $key == $'\e' ]]; then read -rsn2 -t 0.01 rest; key=$rest; fi
  case $key in
    a|A|"[D") ((px>0)) && ((px--));;
    d|D|"[C") ((px<W-1)) && ((px++));;
    w|W|"[A") boost=12;;
    q|Q) break;;
  esac
  # scroll
  for ((i=H-1;i>0;i--)); do rows[i]="${rows[i-1]}"; done
  rows[0]=$(newrow); ((tick++))
  # collision on car row (bottom)
  if [[ "${rows[H-1]:px:1}" == "#" ]]; then
    ((lives--)); hit=3
    rows[H-1]="$blank"
  else ((score++)); fi
  if (( tick%40==0 )); then speed=$(awk -v s=$speed 'BEGIN{s-=0.01; if(s<0.04)s=0.04; print s}'); fi
  # draw
  out=$'\e[H'"ROAD DODGE  score:$score  lives:"
  for ((i=0;i<3;i++)); do (( i<lives )) && out+="<3 " || out+="   "; done
  out+=$'\n'"+"; for ((i=0;i<W;i++)); do out+="-"; done; out+=$'+\n'
  for ((i=0;i<H;i++)); do
    line="${rows[i]}"
    if (( i==H-1 )); then
      c="A"; (( hit>0 )) && { c="X"; ((hit--)); }
      line="${line:0:px}$c${line:px+1}"
    fi
    out+="|$line|"$'\n'
  done
  out+="+"; for ((i=0;i<W;i++)); do out+="-"; done; out+=$'+\n a/d or arrows steer, w or up = speed up, q quits\n'
  printf '%s' "$out"
done
tput rmcup 2>/dev/null; tput cnorm
echo "GAME OVER - score: $score"
trap - EXIT; stty sane
