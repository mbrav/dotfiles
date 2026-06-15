#!/usr/bin/env bash
# Open the persistent "agents" session in a floating popup.
# Navigates to (or creates) a window matching the invoking window name,
# so each main-session window maps 1-to-1 to its agents window.
# $1 - current window name passed via #{window_name}

script_dir="$(dirname "$(realpath "$0")")"
exec "${script_dir}/tmux-named-session.sh" "agents" "$1"
