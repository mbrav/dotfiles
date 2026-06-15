#!/usr/bin/env bash
# Usage: cleanup.sh <task-name>   — kill one agent pane
#        cleanup.sh --all         — kill all panes spawned by this skill (map-file tracked)
set -euo pipefail

script_dir="$(dirname "$(realpath "$0")")"
win="${TMUX_WIN:-$(tmux display-message -p '#{window_name}' 2>/dev/null)}"

if [[ "${1:-}" == "--all" ]]; then
  # Only kill panes that were spawned by this skill (have a map file)
  for mapfile in /tmp/tmux-claude-${win}-*; do
    [[ -f "$mapfile" ]] || continue
    task=$(basename "$mapfile" | sed "s/tmux-claude-${win}-//")
    pane_id=$(cat "$mapfile")
    tmux kill-pane -t "$pane_id" 2>/dev/null && echo "Killed pane ${pane_id} (${task})"
    rm -f "$mapfile"
  done
else
  task="${1:?task-name or --all required}"
  pane_id=$("${script_dir}/pane-id.sh" "$task")
  tmux kill-pane -t "$pane_id"
  rm -f "/tmp/tmux-claude-${win}-${task}"
  echo "Killed pane ${pane_id} (${task})"
fi
