#!/usr/bin/env bash
# Usage: spawn.sh <task-name> '<codex prompt>'
set -euo pipefail

task="${1:?task-name required}"
prompt="${2:?prompt required}"
win="${TMUX_WIN:-$(tmux display-message -p '#{window_name}' 2>/dev/null)}"
target="agents:${win}"

# Ensure the target window exists
if ! tmux list-windows -t agents -F "#{window_name}" 2>/dev/null | grep -qx "$win"; then
  tmux new-window -t agents -n "$win"
fi

# Split a new pane (detached, keep focus in current pane)
pane_id=$(tmux split-window -t "$target" -d -P -F "#{pane_id}")

# Name the pane so it can be referenced by task name
tmux select-pane -t "$pane_id" -T "$task"

# Store pane ID for reliable lookup even if title gets overwritten
echo "$pane_id" >"/tmp/tmux-codex-${win}-${task}"

# Tile all panes so they're all visible
tmux select-layout -t "$target" tiled

# Start Codex
tmux send-keys -t "$pane_id" "codex '${prompt}'" Enter

echo "Spawned '${task}' in pane ${pane_id} (${target})"
