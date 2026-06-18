---
name: tmux-subagents-claude
description: Orchestrates parallel Claude Code subagents in tmux panes under a detached `agents` session. Use when spawning subagents for parallel tasks, delegating work, monitoring running agents, reading replies, sending follow-up prompts, managing context, or cleaning up finished panes. Each agent runs in a named pane mirroring the current window name.
---
# Tmux Agents — Claude

Parallel Claude Code subagents in tmux panes. CLI: `~/.config/scripts/tmux-subagents-claude`.

- [references/tools-and-models.md](references/tools-and-models.md) — model/tools/permissions
- [references/technicalities.md](references/technicalities.md) — architecture, state, concurrency, troubleshooting

## Setup

```bash
~/.config/scripts/tmux-subagents-claude cleanup --all   # before/after batch
```

## Workflow

1. **Spawn** all agents upfront (parallelism starts immediately):

   ```bash
   ~/.config/scripts/tmux-subagents-claude spawn <task> '<prompt>' [options]
   ```

2. **Collect results:**

   ```bash
   ~/.config/scripts/tmux-subagents-claude result <task> --wait    # block until idle, print reply
   ~/.config/scripts/tmux-subagents-claude result <task>           # non-blocking; exit 1 if no reply yet
   ~/.config/scripts/tmux-subagents-claude status [--all]          # snapshot table
   ```

3. **Follow up / inspect / manage:**

   ```bash
   ~/.config/scripts/tmux-subagents-claude prompt  <task> '<text>' [--wait]   # send prompt, optionally block
   ~/.config/scripts/tmux-subagents-claude recap   <task>                     # send /recap to agent
   ~/.config/scripts/tmux-subagents-claude compact <task> [description]       # send /compact to agent
   ~/.config/scripts/tmux-subagents-claude capture <task> [full|log|stop]     # raw terminal (expensive)
   ~/.config/scripts/tmux-subagents-claude cleanup <task>                     # kill one agent
   ~/.config/scripts/tmux-subagents-claude cleanup --all                      # kill all in window
   ~/.config/scripts/tmux-subagents-claude cleanup --prune                    # drop dead entries
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

- `--model MODEL`: e.g. `claude-opus-4-7`, `claude-sonnet-4-6`
- `--tools TOOLS`: comma-separated, e.g. `Read,Edit,Bash`
- `--effort LEVEL`: `low`, `medium`, `high`, `xhigh`, `max`, `auto`
- `--dangerously-skip-permissions`: skip permission prompts (user explicit only)

See [tools-and-models.md](references/tools-and-models.md) for model/tools per task type.

## Resurrect

```bash
~/.config/scripts/tmux-subagents-claude resurrect <task> <session-uuid>
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
