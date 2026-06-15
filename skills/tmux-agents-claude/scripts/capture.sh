#!/usr/bin/env bash
# Usage: capture.sh <task-name> [full|log|stop]
#   (default) — last screenful
#   full       — scrollback up to 3000 lines
#   log        — stream output to /tmp/<task-name>.log
#   stop       — stop streaming
set -euo pipefail

script_dir="$(dirname "$(realpath "$0")")"
task="${1:?task-name required}"
mode="${2:-}"
pane_id=$("${script_dir}/pane-id.sh" "$task")

case "$mode" in
full)
  tmux capture-pane -t "$pane_id" -p -S -3000
  ;;
log)
  logfile="/tmp/${task}.log"
  tmux pipe-pane -t "$pane_id" -o "cat >> ${logfile}"
  echo "Streaming to ${logfile}"
  ;;
stop)
  tmux pipe-pane -t "$pane_id"
  echo "Stopped streaming"
  ;;
*)
  tmux capture-pane -t "$pane_id" -p
  ;;
esac
