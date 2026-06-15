#!/usr/bin/env bash
# Usage: send.sh <task-name> '<text>'
set -euo pipefail

script_dir="$(dirname "$(realpath "$0")")"
task="${1:?task-name required}"
text="${2:?text required}"
pane_id=$("${script_dir}/pane-id.sh" "$task")
tmux send-keys -t "$pane_id" "$text" Enter
