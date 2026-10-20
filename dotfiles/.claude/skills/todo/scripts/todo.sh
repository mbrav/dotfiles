#!/usr/bin/env bash
# Thin wrapper around the tuxedo CLI for the todo skill.
#
# - Pins the global todo.txt (same defaults as _aliases), so the list never
#   silently becomes ./todo.txt in whatever directory the agent happens to be in.
# - Every task carries a stable id:N and exactly one kanban @category.
# - `ctx [DIR]` prints the +project derived from DIR and the categories.
# - `add TEXT...` refuses text without exactly one category, appends the derived
#   +project if the text has none, and puts the next id:N first.
# - `move N CAT` and `do N...` rewrite the category; `line ID` finds a task's
#   line number; `check` lists tasks missing an id or a single category.
# - Anything else is passed straight through to tuxedo.
#
# Usage:
#   todo.sh ctx [DIR]
#   todo.sh add [--bare] TEXT...
#   todo.sh move N CATEGORY | do N... | line ID | check
#   todo.sh <tuxedo command> [args]   e.g. ls --json, pri 2 A
set -euo pipefail

export TODO_DIR="${TODO_DIR:-$HOME/Documents/todo}"
export TODO_FILE="${TODO_FILE:-$TODO_DIR/todo.txt}"
export DONE_FILE="${DONE_FILE:-$(dirname "$TODO_FILE")/done.txt}"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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

# Sets global: project
derive() {
  local dir top vault rel
  dir="$(cd "${1:-$PWD}" && pwd -P)"
  local home
  home="$(cd "$HOME" && pwd -P)"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

  # Project: vault name, then first dir under ~/dev/tmp, then repo, then cwd
  if vault="$(find_vault "$dir")"; then
    project="$(basename "$vault")"
  elif [[ "$dir" == "$home/dev/tmp/"* ]]; then
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

CATEGORIES="triage backlog ready doing review blocked done"

# Prints every @context token in $1, one per line
contexts() {
  printf '%s\n' "$1" | grep -oE '(^|[[:space:]])@[^[:space:]]+' | sed 's/^[[:space:]]*@//' || true
}

# Fails with a message unless $1 has exactly one @context and it is a category
check_category() {
  local found
  found="$(contexts "$1")"
  if [[ -z "$found" ]]; then
    echo "no @category; use one of: $CATEGORIES" >&2
    return 1
  elif [[ "$(printf '%s\n' "$found" | wc -l)" -gt 1 ]]; then
    echo "more than one @context ($(printf '%s' "$found" | tr '\n' ' ')); keep exactly one category" >&2
    return 1
  elif [[ " $CATEGORIES " != *" $found "* ]]; then
    echo "@$found is not a category; use one of: $CATEGORIES" >&2
    return 1
  fi
}

next_id() {
  cat "$TODO_FILE" "$DONE_FILE" 2>/dev/null |
    { grep -oE '(^|[[:space:]])id:[0-9]+' || true; } | sed 's/.*id://' |
    sort -n | tail -1 | awk '{ print $1 + 1 } END { if (NR == 0) print 1 }'
}

# Raw text of line N of todo.txt
raw_line() {
  [[ "$1" =~ ^[0-9]+$ ]] || {
    echo "not a line number: $1" >&2
    exit 2
  }
  local raw
  raw="$(sed -n "${1}p" "$TODO_FILE")"
  [[ -n "$raw" ]] || {
    echo "no task on line $1" >&2
    exit 1
  }
  printf '%s' "$raw"
}

# Rewrites line N with its @context set to CATEGORY, through tuxedo replace,
# which stores the text verbatim (priority and dates included)
set_category() {
  local raw cat="${2#@}"
  [[ " $CATEGORIES " == *" $cat "* ]] || {
    echo "@$cat is not a category; use one of: $CATEGORIES" >&2
    exit 2
  }
  raw="$(raw_line "$1")"
  raw="$(printf '%s' "$raw" | sed -E 's/(^|[[:space:]])@[^[:space:]]+//g')"
  tuxedo replace "$1" "$raw @$cat" >/dev/null
}

cmd_ctx() {
  derive "${1:-}"
  echo "todo_file=$TODO_FILE"
  echo "project=$project"
  echo "categories=$CATEGORIES"
}

cmd_move() {
  [[ $# -eq 2 ]] || {
    echo "usage: todo.sh move N CATEGORY" >&2
    exit 2
  }
  set_category "$1" "$2"
  sed -n "${1}p" "$TODO_FILE"
}

cmd_do() {
  local n
  for n in "$@"; do set_category "$n" "done"; done
  exec tuxedo "do" "$@"
}

cmd_line() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || {
    echo "usage: todo.sh line ID" >&2
    exit 2
  }
  awk -v id="id:$1" '{ for (i = 1; i <= NF; i++) if ($i == id) { print NR; found = 1; exit } }
    END { if (!found) { print "no task with " id " in todo.txt" > "/dev/stderr"; exit 1 } }' "$TODO_FILE"
}

cmd_check() {
  local n=0 bad=0 line ids err
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ -n "$line" ]] || continue
    ids="$(printf '%s\n' "$line" | { grep -oE '(^|[[:space:]])id:[0-9]+' || true; } | wc -l | tr -d ' ')"
    err=""
    [[ "$ids" -eq 1 ]] || err="has $ids ids"
    if ! check_category "$line" 2>/dev/null; then
      err="${err:+$err, }$(check_category "$line" 2>&1 || true)"
    elif [[ "$line" == "x "* && "$(contexts "$line")" != "done" ]]; then
      err="${err:+$err, }completed but not @done"
    fi
    if [[ -n "$err" ]]; then
      echo "$n: $err: $line"
      bad=1
    fi
  done <"$TODO_FILE"
  local dups
  dups="$(cat "$TODO_FILE" "$DONE_FILE" 2>/dev/null | { grep -oE '(^|[[:space:]])id:[0-9]+' || true; } | tr -d ' ' | sort | uniq -d)"
  if [[ -n "$dups" ]]; then
    echo "duplicate ids: $(printf '%s' "$dups" | tr '\n' ' ')"
    bad=1
  fi
  [[ $bad -eq 0 ]] && echo "ok"
  return $bad
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
  local text="$*" pri=""
  [[ ! "$text" =~ (^|[[:space:]])id:[0-9]+ ]] || {
    echo "todo.sh add: leave id:N out, the wrapper assigns it" >&2
    exit 2
  }
  check_category "$text" || exit 2
  derive ""

  # Respect an explicit +project in the text; only fill it in when missing
  if [[ $derived -eq 1 ]]; then
    [[ -n "$project" && ! "$text" =~ (^|[[:space:]])\+[^[:space:]]+ ]] && text+=" +$project"
  fi

  # The id goes first in the description, after any (X) priority
  if [[ "$text" =~ ^\([A-Z]\)\  ]]; then
    pri="${text:0:4}"
    text="${text:4}"
  fi
  exec tuxedo add "${pri}id:$(next_id) $text"
}

command -v tuxedo >/dev/null || {
  echo "tuxedo not found on PATH" >&2
  exit 127
}

case "${1:-}" in
"" | -h | --help) usage ;;
ctx) shift && cmd_ctx "$@" ;;
add | a) shift && cmd_add "$@" ;;
move | mv) shift && cmd_move "$@" ;;
do | done) shift && cmd_do "$@" ;;
line) shift && cmd_line "$@" ;;
check) shift && cmd_check ;;
*) exec tuxedo "$@" ;;
esac
