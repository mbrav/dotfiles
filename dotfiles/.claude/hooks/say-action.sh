#!/usr/bin/env bash
voice="${CLAUDE_SAY_VOICE:-Milena}"

command -v say >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

event="$(field .hook_event_name)"
tool="$(field .tool_name)"

# Basename of whatever path the tool works on, for "Читаю settings.json"
file="$(field '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path')"
file="${file##*/}"

case "$event" in
Stop) text="Готово" ;;
Notification) text="Нужно ваше внимание" ;;
*)
  case "$tool" in
  Bash)
    # First word of the command: "Выполняю git"
    cmd="$(field .tool_input.command)"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    text="Выполняю ${cmd%%[[:space:]]*}"
    ;;
  Read) text="Читаю ${file:-файл}" ;;
  Edit | MultiEdit) text="Редактирую ${file:-файл}" ;;
  Write) text="Создаю ${file:-файл}" ;;
  NotebookEdit) text="Правлю блокнот ${file}" ;;
  Grep | Glob) text="Ищу в файлах" ;;
  WebFetch) text="Открываю страницу" ;;
  WebSearch) text="Ищу в интернете" ;;
  Agent | Task) text="Запускаю агента" ;;
  Skill) text="Запускаю навык $(field .tool_input.skill)" ;;
  TodoWrite) text="Обновляю список задач" ;;
  AskUserQuestion) text="У меня вопрос" ;;
  ExitPlanMode) text="План готов" ;;
  mcp__*) text="Вызываю инструмент ${tool##*__}" ;;
  *) text="Выполняю ${tool:-действие}" ;;
  esac
  ;;
esac

if [[ "$event" == Stop || "$event" == Notification ]]; then
  pkill -x say 2>/dev/null
elif pgrep -x say >/dev/null 2>&1; then
  exit 0
fi

# Who is speaking: the project (git repo or folder name), plus the subagent
# type when a subagent made the call
speaker() {
  local cwd root name agent
  cwd="$(field .cwd)"
  root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${cwd:-$PWD}")"
  name="${root##*/}"
  agent="$(field .agent_type)"
  [[ -n "$agent" ]] && name="$name, агент $agent"
  printf '%s' "$name"
}

(
  who="$(speaker)"
  say -v "$voice" -- "${who:+$who: }$text"
) </dev/null >/dev/null 2>&1 &
disown
exit 0
