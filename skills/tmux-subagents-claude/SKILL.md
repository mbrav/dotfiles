---
name: tmux-subagents-claude
description: Orchestrates parallel Claude Code subagents in tmux panes under a detached `agents` session. Use when spawning subagents for parallel tasks, delegating work, monitoring running agents, reading replies, sending follow-up prompts, managing context, or cleaning up finished panes. Each agent runs in a named pane mirroring the current window name.
---
# Tmux Agents — Claude

Parallel Claude Code subagents in tmux panes. CLI: `tmux-subagents-claude` (Go binary on `PATH`).

- [references/tools-and-models.md](references/tools-and-models.md) — model/tools/permissions
- [references/technicalities.md](references/technicalities.md) — architecture, state, concurrency, troubleshooting

## Install

```bash
go install github.com/mbrav/dotfiles/go/tmux-subagents-claude@latest   # -> ~/go/bin
```

Source in `go/`; `~/go/bin` is on `PATH` (bash + fish). For local dev: `cd go && go build -o ~/go/bin/tmux-subagents-claude ./tmux-subagents-claude`.

## Setup

```bash
tmux-subagents-claude cleanup --all   # before/after batch
```

## Workflow

1. **Spawn** all agents upfront (parallelism starts immediately):

   ```bash
   tmux-subagents-claude spawn <task> '<prompt>' [options]
   ```

2. **Collect results:**

   ```bash
   tmux-subagents-claude result <task> --wait    # block until idle, print reply
   tmux-subagents-claude result <task>           # non-blocking; exit 1 if no reply yet
   tmux-subagents-claude status                  # snapshot table (current project)
   tmux-subagents-claude status <task>           # bare status word — grep/script-friendly
   ```

3. **Follow up / inspect / manage:**

   ```bash
   tmux-subagents-claude prompt  <task> '<text>' [--wait]   # send prompt, optionally block
   tmux-subagents-claude recap   <task>                     # send /recap to agent
   tmux-subagents-claude compact <task> [description]       # send /compact to agent
   tmux-subagents-claude capture <task> [full|log|stop]     # raw terminal (expensive)
   tmux-subagents-claude cleanup <task>                     # kill one agent
   tmux-subagents-claude cleanup --all                      # kill all in window
   tmux-subagents-claude cleanup --prune                    # drop dead entries
   ```

## Rules

- **Follow-up + block**: `prompt … --wait` baselines prior reply — never stale. Don't use `result --wait` after `prompt` (returns prev).
- **Don't background** `--wait` (shell `&`): reply lost. Run foreground.
- **`empty`** = no reply yet. **`idle`** = reply ready. Neither proves latest prompt landed — confirm via body.
- **`capture`** = expensive, debug only. Don't use on idle agent (`result` is cheaper); don't use before `prompt`.
- **Spawn all** independent agents upfront, even if prompting later.
- **`result` exit 0** = `end_turn` exists. NOT done — verify body.
- **`cleanup --all`** = current window only. **`--prune`** = cross-window, preserves live agents.

## Stuck agent

`prompt` repaints + clears line + verifies before sending. `prompt-not-submitted` exit = pane wedged: `capture` to inspect, then `cleanup` + `resurrect`. See [technicalities.md](references/technicalities.md#prompt-submission).

## Spawn options

- `--model MODEL`: `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-5`, `claude-sonnet-4-6`, `claude-sonnet-4-5`, `claude-haiku-4-5`
- `--tools TOOLS`: comma-separated, e.g. `Read,Edit,Bash`
- `--effort LEVEL`: `low`, `medium`, `high`, `xhigh`, `max`, `auto`
- `--permission-mode MODE`: `auto` (default), `acceptEdits`, `dontAsk`, `default`, `plan`. Default `auto` proceeds without prompting and avoids the "Bypass Permissions mode" warning that wedges a fresh pane.

See [tools-and-models.md](references/tools-and-models.md) for model/tools per task type.

## Resurrect

```bash
tmux-subagents-claude resurrect <task> <session-uuid>
```

Session ID from spawn output or `status`. Creates new pane, resumes exact conversation (JSONL preserved).

## Status values

| Value | Meaning |
|-------|---------|
| `empty` | live, no reply yet |
| `idle` | live, reply ready |
| `busy` | working |
| `waiting` | blocked on permission/question — NOT done; `result --wait` may return stale reply |
| `starting` | status file pending |
| `dead` | pane gone — run `cleanup --prune` |

`CONTEXT` column: context-window usage from pane footer, e.g. `90.0k/1000.0k (9.0%)`. `-` = not rendered.
