#!/usr/bin/env bash
# Usage: status.sh [task-name]
#   No args   — list all panes in current agents window with state
#   task-name — print "running (<cmd>)" or "done" for that pane
set -euo pipefail

script_dir="$(dirname "$(realpath "$0")")"
win="${TMUX_WIN:-$(tmux display-message -p '#{window_name}' 2>/dev/null)}"

if [[ -z "${1:-}" ]]; then
  tmux list-panes -t "agents:${win}" \
    -F "#{pane_id}	#{pane_title}	#{pane_current_command}" 2>/dev/null |
    awk -F'\t' '{
      state = ($3 == "fish" || $3 == "bash" || $3 == "zsh" || $3 == "sh") ? "done" : "running"
      printf "%-10s %-30s %s\n", $1, ($2 == "" ? "(unnamed)" : $2), state
    }'
else
  pane_id=$("${script_dir}/pane-id.sh" "$1")
  cmd=$(tmux display-message -p -t "$pane_id" "#{pane_current_command}" 2>/dev/null)
  case "$cmd" in
  fish | bash | zsh | sh) echo "done" ;;
  "")
    echo "not found"
    exit 1
    ;;
  *) echo "running ($cmd)" ;;
  esac
fi
