#!/usr/bin/env bash
# Returns the pane_id for a given task name.
# Checks the stored map file first; falls back to searching by pane title.
set -euo pipefail

task="${1:?task-name required}"
win="${TMUX_WIN:-$(tmux display-message -p '#{window_name}' 2>/dev/null)}"
mapfile="/tmp/tmux-codex-${win}-${task}"

if [[ -f "$mapfile" ]]; then
  pane_id=$(cat "$mapfile")
  if tmux list-panes -t "agents:${win}" -F "#{pane_id}" 2>/dev/null | grep -qx "$pane_id"; then
    echo "$pane_id"
    exit 0
  fi
fi

# Fallback: search by pane title
pane_id=$(tmux list-panes -t "agents:${win}" -F "#{pane_id} #{pane_title}" 2>/dev/null |
  awk -v t="$task" '$2 == t { print $1; exit }')

if [[ -n "$pane_id" ]]; then
  echo "$pane_id"
else
  echo "pane not found: ${task}" >&2
  exit 1
fi
