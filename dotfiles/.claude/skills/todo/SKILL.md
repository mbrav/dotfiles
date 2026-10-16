---
name: todo
description: Manage the user's global todo.txt task list through the tuxedo CLI — add, list, filter, prioritize, complete, append to and archive tasks. Every task Claude adds is tagged with a +project and @context derived from the current directory (@mbrav, @work, @experiment, @obsidian, @trading). Use this skill whenever the user mentions todos, tasks, a todo list, todo.txt or tuxedo, says "add a todo", "remind me to", "note this for later", "put that on my list", "what's on my plate", "what's left", "mark X done", or asks to track a follow-up, tech debt or an action item from the current session — even if they never say "todo".
---

# todo

The user keeps one global [todo.txt](https://github.com/todotxt/todo.txt) list, edited by hand in the tuxedo TUI (also from nvim via `<leader>td`) and by you through the CLI. Treat it as theirs: small, precise edits, never rewrite the file directly.

Run everything through the bundled wrapper:

```bash
T=~/.claude/skills/todo/scripts/todo.sh
```

It pins `TODO_FILE` to the global list (`~/Documents/todo/todo.txt` unless the env already says otherwise). Calling bare `tuxedo` from a project directory without that env would silently create a stray `./todo.txt`, so don't.

| Need | Command |
| --- | --- |
| See what the current dir maps to | `$T ctx` |
| Add a task (auto-tagged) | `$T add "TEXT"` |
| Add exactly as written, nothing appended | `$T add --bare "TEXT"` |
| List (filter by `+proj`, `@ctx`, or words) | `$T ls --json [TERM...]` |
| Include completed tasks | `$T lsa --json [TERM...]` |
| Set / clear priority | `$T pri N A` / `$T dp N` |
| Complete | `$T do N...` |
| Append / replace text | `$T app N TEXT` / `$T replace N TEXT` |
| Move completed tasks to done.txt | `$T archive` |
| List projects / contexts in use | `$T lsprj` / `$T lsc` |

`N` is the task's line number in todo.txt. Numbers stay stable while tasks are completed but shift after `archive` or `del`, and the user may have edited the file in the TUI since your last look. So list right before acting on a number, and match the task by its text, not by a number you remember from earlier in the conversation.

## Contexts and projects

`$T add` appends whatever the task text doesn't already carry. Rules, first match wins:

| Where you are | @context | +project |
| --- | --- | --- |
| inside an Obsidian vault (a parent has `.obsidian/`) or a path containing "obsidian" | `@obsidian` | vault folder name |
| a path component about trading (`trading`, `algo-trading`, `trades`, `trader`…; not `traditional-*`) | `@trading` | repo name |
| `~/dev/tmp/...` | `@experiment` | first folder under `~/dev/tmp` |
| `~/dev/github.com/...` | `@mbrav` | repo name |
| anywhere else (`~/dev/git.sib.team`, `~`, …) | `@work` | repo name, else dir name, none in `~` |

Directory isn't the whole story. The user wants trading-related tasks under `@trading`, so if the *task itself* is about trading — positions, brokers, exchanges, strategies, backtests, P&L, market data — write `@trading` into the text explicitly and the wrapper will leave it alone. Likewise, if the user names a project or context ("add this to +homelab", "that's a work thing"), put it in the text. Explicit beats derived. Don't add a second `@context` just because the directory suggests a different one; one context per task keeps filters meaningful.

## Adding tasks

1. Write the task as a short imperative line the user would recognize in a month without this conversation: "Rotate the staging DB password", not "do the thing we discussed". Pull in the specific file, ticket or error if it's what makes the task findable later.
2. Priority only when the user signals it — "urgent", "blocker", "first thing" → `(A)`, "important"/"soon" → `(B)`, "someday"/"low priority" → `(C)` or none. Put it at the very start: `(A) Fix …`. Unprioritized is the normal case; don't inflate.
3. Due dates: resolve them yourself to `due:YYYY-MM-DD` (you know today's date; on macOS `date -v+1d +%F`; `date -v+fri +%F` is *today* when today is Friday, so "next Friday" needs thought). tuxedo only converts some prose ("due tomorrow") and stores shorthands like `due:fri` verbatim, which breaks date sorting.
4. Keep it short. The line is read in a TUI next to a dozen others, so one sentence with the file name in parentheses is plenty; leave the reasoning in the conversation.
5. Avoid `word:` anywhere in the text (`mr-patrol-context: add…`, `image:`, `remote:`). todo.txt parses any `key:value` token as metadata, so the TUI dims it and filters treat it as a field. Write `mr-patrol-context - add…` instead, and rephrase `image:` as "image refs".
6. Run `$T add "…"`, then show the user the line tuxedo printed back so they can see the tags that were added.

Several follow-ups at once ("add these three") → one `$T add` per task, then one summary.

When the user asks you to capture something mid-task ("remember to clean that up later"), add it and get back to the main work; it's a side effect, not a new topic. Don't invent todos the user didn't ask for. If you notice something worth tracking, suggest it in a sentence and let them say yes.

## Listing and reporting

Use `--json` and present the result yourself rather than pasting raw lines: number, priority, task text, due date if any, and the tags.

Pick the scope from the question:

- "what's on my list" / "my todos" → everything open
- "todos for this project" / "what's left here" → `+<project>` from `$T ctx`
- "work stuff", "experiments", "trading" → the matching `@context`
- "overdue" / "due this week" → filter the JSON on `due`

Sort overdue first, then by priority, then by due date. Flag overdue tasks. When a filter returns nothing, say so and mention how many tasks exist overall, so an empty filter isn't mistaken for an empty list.

## Completing, editing, deleting

- **Done**: list, match by text, `$T do N`. If more than one task plausibly matches, ask which one rather than guessing — completing the wrong task hides it from the user.
- **Edit**: prefer `app`/`pri`/`dp` over `replace`; when you must `replace`, carry the existing date and tags over unchanged.
- **Delete**: `$T del N` erases the task with no record. Prefer `do` unless the user says delete or remove. Confirm the exact line before running `$T del -f N`.
- **Archive** only when asked; the user may like seeing completed tasks in the TUI.
