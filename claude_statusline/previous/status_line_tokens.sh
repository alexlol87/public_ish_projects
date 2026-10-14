#!/bin/bash
input=$(cat)

bar() {
  local pct="$1" filled i out=""
  filled=$(printf '%.0f' "$(echo "$pct / 10" | bc -l)")
  for ((i=0; i<10; i++)); do
    if (( i < filled )); then out+="█"; else out+="░"; fi
  done
  printf '\033[38;2;180;180;255m%s\033[0m' "$out"
}

commas() {
  local n="$1" out="" i len rem
  len=${#n}
  for ((i=0; i<len; i++)); do
    out+="${n:i:1}"
    rem=$((len - i - 1))
    if (( rem > 0 && rem % 3 == 0 )); then out+=","; fi
  done
  echo "$out"
}

ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$ctx_pct" ]; then
  line1=$(printf '📊 %s %.0f%% (%s/%s tok)' "$(bar "$ctx_pct")" "$ctx_pct" "$(commas "$ctx_tokens")" "$(commas "$ctx_size")")
else
  line1="📊 --"
fi

if [ -n "$session_pct" ]; then
  line2=$(printf '⏱️  %s %.0f%% session' "$(bar "$session_pct")" "$session_pct")
else
  line2="⏱️  --"
fi

if [ -n "$week_pct" ]; then
  line3=$(printf '📅 %s %.0f%% week' "$(bar "$week_pct")" "$week_pct")
else
  line3="📅 --"
fi

printf '%s  |  %s  |  %s\n' "$line1" "$line2" "$line3"
