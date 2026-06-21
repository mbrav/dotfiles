#!/usr/bin/env bash
input=$(cat)

# Per-call token stats
cur_out=$(echo "$input"   | jq -r '.context_window.current_usage.output_tokens // empty')
cur_in=$(echo "$input"    | jq -r '.context_window.current_usage.input_tokens // empty')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cache_write=$(echo "$input"| jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')

# Context window
used_pct=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input"  | jq -r '.context_window.context_window_size // empty')

# Subscription / rate limits presence
has_rate=$(echo "$input"  | jq -r 'if .rate_limits then "sub" else empty end')

# Permissions mode
perm_mode=$(echo "$input" | jq -r '.permissions.defaultMode // empty')

# Helper: format a number as compact notation (1234 -> 1.2k, 1000000 -> 1.0M)
fmt() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "0" ]; then
    echo ""
    return
  fi
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN { printf \"%.1fk\", $n/1000 }"
  else
    echo "$n"
  fi
}

# Estimate cost (Sonnet pricing: $3/MTok input, $15/MTok output, $3.75/MTok cache_write, $0.30/MTok cache_read)
cost_part=""
if [ -n "$cur_in" ] || [ -n "$cur_out" ]; then
  cost=$(awk "BEGIN {
    i  = ${cur_in:-0}
    o  = ${cur_out:-0}
    cr = ${cache_read:-0}
    cw = ${cache_write:-0}
    total = (i * 3 + o * 15 + cw * 3.75 + cr * 0.30) / 1000000
    printf \"\$%.3f\", total
  }")
  cost_part="$cost"
fi

# Build parts
parts=""

append() {
  if [ -n "$2" ]; then
    [ -n "$parts" ] && parts="$parts "
    parts="$parts$1$2"
  fi
}

append "↑" "$(fmt "$cur_out")"
append "↓" "$(fmt "$cur_in")"
append "R" "$(fmt "$cache_read")"
append "W" "$(fmt "$cache_write")"
[ -n "$cost_part" ] && { [ -n "$parts" ] && parts="$parts "; parts="$parts$cost_part"; }
[ -n "$has_rate"  ] && { [ -n "$parts" ] && parts="$parts "; parts="$parts($has_rate)"; }

# Context: usedM/totalM (used%)
ctx_part=""
if [ -n "$used_pct" ] && [ -n "$ctx_size" ]; then
  size_fmt=$(fmt "$ctx_size")
  used_tokens=$(awk "BEGIN { printf \"%.1fk\", ($used_pct/100) * $ctx_size / 1000 }")
  ctx_part="${used_tokens}/${size_fmt} ($(awk "BEGIN { printf \"%.1f\", $used_pct }")%)"
fi
[ -n "$ctx_part" ] && { [ -n "$parts" ] && parts="$parts "; parts="$parts$ctx_part"; }

[ -n "$perm_mode" ] && { [ -n "$parts" ] && parts="$parts "; parts="$parts($perm_mode)"; }

printf "%s" "$parts"
