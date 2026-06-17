#!/usr/bin/env bash
# Attach to (or create) a named tmux session.
# $1 - session name (e.g. "scratch", "agents")
# $2 - optional "--browse": just attach, no window creation/selection by invoking name

script_dir="$(dirname "$(realpath "$0")")"
source "${script_dir}/../scripts/_util"

session="${1:?Session name required}"
browse="${2:-}"

if ! tmux has-session -t "$session" 2>/dev/null; then
  if [[ "$browse" == "--browse" ]]; then
    yes_no_prompt "No '${session}' session exists. Create it?" || exit 0
  fi
  tmux new-session -d -s "$session"
  info_msg "Created session ${BOLD}${session}${CLEAR}" ""
fi

if [[ "$browse" != "--browse" ]]; then
  win="$(tmux display-message -p '#{window_name}')"
  if ! tmux list-windows -t "$session" -F '#{window_name}' | grep -qx "$win"; then
    tmux new-window -t "$session" -n "$win"
    info_msg "Created window ${BOLD}${win}${CLEAR} in session: ${BOLD}${session}${CLEAR}" ""
  fi
  tmux select-window -t "${session}:${win}"
fi

exec tmux attach-session -t "$session"
