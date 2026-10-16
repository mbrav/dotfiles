#!/usr/bin/env bash
# Thin wrapper around the tuxedo CLI for the todo skill.
#
# - Pins the global todo.txt (same defaults as _aliases), so the list never
#   silently becomes ./todo.txt in whatever directory the agent happens to be in.
# - `ctx [DIR]` prints the +project / @context derived from DIR.
# - `add TEXT...` appends whatever +project and @context the text does not
#   already carry, then calls `tuxedo add`.
# - Anything else is passed straight through to tuxedo.
#
# Usage:
#   todo.sh ctx [DIR]
#   todo.sh add [--bare] TEXT...
#   todo.sh <tuxedo command> [args]   e.g. ls --json, do 3, pri 2 A
set -euo pipefail

export TODO_DIR="${TODO_DIR:-$HOME/Documents/todo}"
export TODO_FILE="${TODO_FILE:-$TODO_DIR/todo.txt}"
export DONE_FILE="${DONE_FILE:-$(dirname "$TODO_FILE")/done.txt}"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

# todo.txt tags end at whitespace, so collapse anything outside a safe set
sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//'
}

# Walk up from $1 looking for an Obsidian vault marker; prints the vault root
find_vault() {
  local d="$1"
  while [[ "$d" != "/" && -n "$d" ]]; do
    [[ -d "$d/.obsidian" ]] && {
      printf '%s' "$d"
      return 0
    }
    d="$(dirname "$d")"
  done
  return 1
}

# A path component that names trading: trading, algo-trading, trades, trader...
# but not "traditional-markets"
is_trading_path() {
  local IFS=/ part
  # shellcheck disable=SC2086
  for part in $1; do
    part="$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')"
    [[ "$part" == *trading* ]] && return 0
    [[ "$part" =~ (^|[-_.])trade(s|r|rs)?([-_.]|$) ]] && return 0
  done
  return 1
}

# Sets globals: project context
derive() {
  local dir top vault rel
  dir="$(cd "${1:-$PWD}" && pwd -P)"
  local home
  home="$(cd "$HOME" && pwd -P)"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

  # Context: most specific rule first
  if vault="$(find_vault "$dir")" || [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == *obsidian* ]]; then
    context=obsidian
  elif is_trading_path "${dir#"$home"}"; then
    context=trading
  elif [[ "$dir" == "$home/dev/tmp" || "$dir" == "$home/dev/tmp/"* ]]; then
    context=experiment
  elif [[ "$dir" == "$home/dev/github.com" || "$dir" == "$home/dev/github.com/"* ]]; then
    context=mbrav
  else
    context=work
  fi

  # Project: vault name, then first dir under ~/dev/tmp, then repo, then cwd
  if [[ -n "${vault:-}" ]]; then
    project="$(basename "$vault")"
  elif [[ "$context" == experiment && "$dir" == "$home/dev/tmp/"* ]]; then
    rel="${dir#"$home/dev/tmp/"}"
    project="${rel%%/*}"
  elif [[ -n "$top" ]]; then
    project="$(basename "$top")"
  elif [[ "$dir" != "$home" && "$dir" != "$home/dev/tmp" && "$dir" != "/" ]]; then
    project="$(basename "$dir")"
  else
    project=""
  fi
  project="$(sanitize "$project")"
}

cmd_ctx() {
  derive "${1:-}"
  echo "todo_file=$TODO_FILE"
  echo "project=$project"
  echo "context=$context"
}

cmd_add() {
  # --bare: append nothing, the text already says everything
  local derived=1
  if [[ "${1:-}" == "--bare" ]]; then
    derived=0
    shift
  fi
  [[ $# -gt 0 ]] || {
    echo "todo.sh add: missing task text" >&2
    exit 2
  }
  local text="$*"
  derive ""

  # Respect explicit tags in the text; only fill in what is missing
  if [[ $derived -eq 1 ]]; then
    [[ -n "$project" && ! "$text" =~ (^|[[:space:]])\+[^[:space:]]+ ]] && text+=" +$project"
    [[ ! "$text" =~ (^|[[:space:]])@[^[:space:]]+ ]] && text+=" @$context"
  fi
  exec tuxedo add "$text"
}

command -v tuxedo >/dev/null || {
  echo "tuxedo not found on PATH" >&2
  exit 127
}

case "${1:-}" in
"" | -h | --help) usage ;;
ctx) shift && cmd_ctx "$@" ;;
add | a) shift && cmd_add "$@" ;;
*) exec tuxedo "$@" ;;
esac
