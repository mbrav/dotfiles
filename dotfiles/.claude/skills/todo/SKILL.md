---
name: todo
description: Manage the user's global todo.txt task list through the tuxedo CLI — add, list, filter, prioritize, complete, append to and archive tasks. Every task carries a stable id:N and exactly one kanban category as its @context (@triage, @backlog, @ready, @doing, @review, @blocked, @done), plus a +project derived from the current directory. Use this skill whenever the user mentions todos, tasks, a todo list, todo.txt or tuxedo, says "add a todo", "remind me to", "note this for later", "put that on my list", "what's on my plate", "what's left", "mark X done", or asks to track a follow-up, tech debt or an action item from the current session — even if they never say "todo".
---

# todo

The user keeps one global [todo.txt](https://github.com/todotxt/todo.txt) list, edited by hand in the tuxedo TUI (also from nvim via `<leader>td`) and by you through the CLI. Treat it as theirs: small, precise edits, never rewrite the file directly.

**Strict rule: every read and write goes through the bundled wrapper.** Never call `tuxedo add` directly and never edit todo.txt or done.txt with an editor, `sed`, `echo >>` or a script. The wrapper is what assigns ids and enforces categories; bypassing it leaves tasks without either.

```bash
T=~/.claude/skills/todo/scripts/todo.sh
```

It pins `TODO_FILE` to the global list (`~/Documents/todo/todo.txt` unless the env already says otherwise). Calling bare `tuxedo` from a project directory without that env would silently create a stray `./todo.txt`, so don't.

| Need | Command |
| --- | --- |
| See the derived +project and the categories | `$T ctx` |
| Add a task (gets the next id, +project appended) | `$T add "TEXT @category"` |
| Add without deriving a +project | `$T add --bare "TEXT @category"` |
| Move a task to another column | `$T move N CATEGORY` |
| Find a task's line number by its id | `$T line ID` |
| Check every task has an id and one category | `$T check` |
| List (filter by `+proj`, `@category`, or words) | `$T ls --json [TERM...]` |
| Include completed tasks | `$T lsa --json [TERM...]` |
| Set / clear priority | `$T pri N A` / `$T dp N` |
| Complete (also moves it to `@done`) | `$T do N...` |
| Append / replace text | `$T app N TEXT` / `$T replace N TEXT` |
| Move completed tasks to done.txt | `$T archive` |
| List projects / categories in use | `$T lsprj` / `$T lsc` |

Two numbers matter:

- **The id** (`id:42`) is the task's permanent number. The wrapper assigns the next free one across todo.txt and done.txt and puts it at the front of the description. Use it whenever you refer to a task, to the user or to other agents ("#42"). Never write, change or reuse an id yourself.
- **`N`** is the line number tuxedo's commands take. Line numbers shift after `archive` or `del`, and the user may have edited the file in the TUI since your last look. So resolve it right before acting, with `$T line ID`, and don't reuse a line number you remember from earlier in the conversation.

tuxedo itself has no stable ids or kanban columns (checked in 2026.8.1), which is why the wrapper adds them. If a later tuxedo version adds either, prefer the built-in feature and update this skill.

## Kanban categories

**Strict rule: every task has exactly one @context, and it is one of these kanban categories.** The wrapper refuses an add or move with no category, two categories, or any other @context (`@work`, `@team`, `@trading`…). Areas like work, trading or a team belong in the `+project`, not in the context.

| Category | Means |
| --- | --- |
| `@triage` | new and unsorted: a finding, an incident or a request nobody has sized yet |
| `@backlog` | accepted, not scheduled yet |
| `@ready` | scheduled and can be picked up now, nothing blocks it |
| `@doing` | someone is working on it |
| `@review` | the work exists and waits on review, test, a merge or the user's check |
| `@blocked` | can't move until someone else acts or decides; say who in the text |
| `@done` | completed (`$T do` sets it) |

Pick the category when you add a task. If you can't tell, use `@triage`; never leave it out. When a task's state changes (picked up, sent to review, blocked, unblocked), `$T move` it the same turn so the board stays true.

The +project comes from the directory and is appended when the text has none: an Obsidian vault's folder name, the first folder under `~/dev/tmp`, the git repo's name, else the directory's name (none in `~`). If the user names a project ("add this to +homelab"), put it in the text; explicit beats derived.

## Adding tasks

1. Write the task as a short imperative line the user would recognize in a month without this conversation: "Rotate the staging DB password", not "do the thing we discussed". Pull in the specific file, ticket or error if it's what makes the task findable later.
2. Priority only when the user signals it — "urgent", "blocker", "first thing" → `(A)`, "important" → `(B)`, "soon"/"next" → `(C)`, "when there's time"/"nice to have" → `(D)`, "someday"/"low priority" → `(E)` or none. Put it at the very start: `(A) Fix …`. Unprioritized is the normal case; don't inflate.
3. Due dates: resolve them yourself to `due:YYYY-MM-DD` (you know today's date; on macOS `date -v+1d +%F`; `date -v+fri +%F` is *today* when today is Friday, so "next Friday" needs thought). tuxedo only converts some prose ("due tomorrow") and stores shorthands like `due:fri` verbatim, which breaks date sorting. "Next Friday" (or "by Friday") means the first Friday after today, so on a Tuesday it's three days away. Use the one after that only when the user says "the Friday after next" or "a week on Friday". Say the resolved date in your reply, so a different reading is easy to correct.
4. Keep it short. The line is read in a TUI next to a dozen others, so one sentence with the file name in parentheses is plenty; leave the reasoning in the conversation.
5. Avoid `word:` anywhere in the text (`mr-patrol-context: add…`, `image:`, `remote:`). todo.txt parses any `key:value` token as metadata, so the TUI dims it and filters treat it as a field. Write `mr-patrol-context - add…` instead, and rephrase `image:` as "image refs".
6. Run `$T add "… @category"`, then show the user the line printed back so they can see the id and tags.

Several follow-ups at once ("add these three") → one `$T add` per task, then one summary.

When the user asks you to capture something mid-task ("remember to clean that up later"), add it and get back to the main work; it's a side effect, not a new topic. Don't invent todos the user didn't ask for. If you notice something worth tracking, suggest it in a sentence and let them say yes.

## Listing and reporting

Use `--json` and present the result yourself rather than pasting raw lines: id, priority, task text, due date if any, and the +project. For a status overview, group by category in board order (triage, backlog, ready, doing, review, blocked).

Pick the scope from the question:

- "what's on my list" / "my todos" → everything open
- "todos for this project" / "what's left here" → `+<project>` from `$T ctx`
- "what's blocked", "what's in review", "the backlog" → the matching `@category`
- "work stuff", "trading" → the matching `+project`, or words in the text
- "overdue" / "due this week" → filter the JSON on `due`

Sort overdue first, then by priority, then by due date. Flag overdue tasks. When a filter returns nothing, say so and mention how many tasks exist overall, so an empty filter isn't mistaken for an empty list.

## Completing, editing, deleting

- **Done**: list, match by id or text, `$T do N` (it also moves the task to `@done`). If more than one task plausibly matches, ask which one rather than guessing — completing the wrong task hides it from the user.
- **Edit**: prefer `app`/`pri`/`dp`/`move` over `replace`; when you must `replace`, carry the existing date, `id:N`, category and tags over unchanged, then run `$T check`.
- **Delete**: `$T del N` erases the task with no record. Prefer `do` unless the user says delete or remove. Confirm the exact line before running `$T del -f N`.
- **Archive** only when asked; the user may like seeing completed tasks in the TUI.
