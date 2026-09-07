#!/usr/bin/env bash
# herd.sh — thin wrapper over `herdr` to spawn/drive Claude subagents as
# sibling panes in the CURRENT tab. All JSON parsing lives here so the skill
# body stays one-liners. Requires HERDR_ENV=1 (inside a herdr pane).
set -euo pipefail

need_env() { [ "${HERDR_ENV:-}" = 1 ] || {
  echo "not inside herdr (HERDR_ENV!=1)" >&2
  exit 1
}; }

# spawn <name> [prompt] [--model M] [--dir CWD]
# Splits the current tab (down if wide-ish, else right), starts a claude agent,
# and — if a prompt is given — submits it WITHOUT waiting (fan out, collect later).
spawn() {
  need_env
  local name=$1
  shift
  local prompt="" model="claude-haiku-4-5" dir="$PWD" dirn
  [ $# -gt 0 ] && [ "${1:0:2}" != "--" ] && {
    prompt=$1
    shift
  }
  while [ $# -gt 0 ]; do case $1 in
    --model)
      model=$2
      shift 2
      ;;
    --dir)
      dir=$2
      shift 2
      ;;
    *) shift ;; esac done
  # split direction: down when the tab has few panes, else right (avoid slivers)
  local dircount
  dircount=$(herdr pane list --workspace "$HERDR_WORKSPACE_ID" | jq -r '.result.panes | length')
  local direction=down
  [ "$dircount" -gt 3 ] && direction=right
  local pane
  pane=$(herdr pane split --current --direction "$direction" --cwd "$dir" --no-focus | jq -r '.result.pane.pane_id')
  herdr agent start "$name" --kind claude --pane "$pane" --timeout 90000 -- --model "$model" >/dev/null
  echo "$name -> $pane (claude/$model)"
  [ -n "$prompt" ] && herdr agent prompt "$name" "$prompt" >/dev/null && echo "  prompted"
  return 0
}

# ask <name> <prompt>: submit, block for reply, print it. Retries once on the
# 5s stall guard a fresh agent's first prompt can trip.
ask() {
  need_env
  herdr agent prompt "$1" "$2" --wait --timeout 300000 >/dev/null 2>/tmp/herd.$$ ||
    { grep -q agent_prompt_stalled /tmp/herd.$$ && herdr agent prompt "$1" "$2" --wait --timeout 300000 >/dev/null; }
  rm -f /tmp/herd.$$
  reply "$1"
}
reply() {
  need_env
  herdr agent read "$1" --source recent-unwrapped --lines "${2:-80}"
} # reply <name> [lines]
wait() {
  need_env
  herdr agent wait "$1" --timeout "${2:-300000}" | jq -r '.result.agent.agent_status // "?"'
}
kind() {
  need_env
  herdr agent get "$1" | jq -r '.result.agent.agent_status // "?"'
} # bare status word
ls_() {
  need_env
  herdr agent list | jq -r '.result.agents[] | "\(.pane_id)  \(.agent_status | . + " "*(8-length))  \(.terminal_title_stripped // "?")"'
}
kill_() {
  need_env
  local p
  p=$(herdr agent get "$1" | jq -r '.result.agent.pane_id')
  herdr pane close "$p" >/dev/null && echo "closed $1 ($p)"
}

cmd=${1:-}
shift || true
case "$cmd" in
spawn) spawn "$@" ;; ask) ask "$@" ;; reply) reply "$@" ;; wait) wait "$@" ;;
status) kind "$@" ;; ls | list) ls_ ;; kill) kill_ "$@" ;;
*)
  echo "usage: herd.sh {spawn <name> [prompt] [--model M] [--dir D]|ask <name> <prompt>|reply <name> [lines]|wait <name> [ms]|status <name>|ls|kill <name>}" >&2
  exit 2
  ;;
esac
