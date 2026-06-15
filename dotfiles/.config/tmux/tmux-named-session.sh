#!/usr/bin/env bash
# Attach to (or create) a named tmux session, navigating to the window that
# matches the invoking window name. Creates the window if it doesn't exist.
# $1 - session name (e.g. "scratch", "agents")
# $2 - window name to select (e.g. #{window_name} from the calling binding)

script_dir="$(dirname "$(realpath "$0")")"
source "${script_dir}/../scripts/_util"

session="${1:?Session name required}"
win="${2:-main}"

if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -n "$win" -e "TMUX_WIN=$win"
  info_msg "Created session ${BOLD}${session}${CLEAR} with window: ${BOLD}${win}${CLEAR}" ""
elif ! tmux list-windows -t "$session" -F '#{window_name}' | grep -qx "$win"; then
  tmux new-window -t "$session" -n "$win" -e "TMUX_WIN=$win"
  info_msg "Created window ${BOLD}${win}${CLEAR} in session: ${BOLD}${session}${CLEAR}" ""
fi

tmux select-window -t "${session}:${win}"
exec tmux attach-session -t "$session"
