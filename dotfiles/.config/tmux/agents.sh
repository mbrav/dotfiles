#!/usr/bin/env bash
# Dracula custom plugin: number of running subagents per agents window.
#   3 agents in one window      -> 🤖3
#   windows with 1,5,2 agents   -> 🤖1|5|2
#   no agents session           -> "" (segment collapses)
#
# Subagents are panes inside windows of the detached `agents` tmux session
# (managed by the tmux-agents-* skills). The persistent `__keeper__` anchor
# window, if present, is excluded from the counts.
export LC_ALL=en_US.UTF-8

KEEPER_WINDOW="__keeper__"

main() {
  tmux has-session -t agents 2>/dev/null || return

  local label
  label=$(tmux show-option -gqv "@dracula-agents-label")
  label=${label:-🤖}

  local counts=() wname pcount
  while read -r wname pcount; do
    [[ "$wname" == "$KEEPER_WINDOW" ]] && continue
    counts+=("$pcount")
  done < <(tmux list-windows -t agents -F '#{window_name} #{window_panes}')

  ((${#counts[@]})) || return

  local IFS='|'
  echo "${label} ${counts[*]}"
}

main
