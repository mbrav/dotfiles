---
name: tmux-subagents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the detached agents session window that mirrors the current window name.
---
# Tmux Agents — Claude

Spawn/manage parallel Claude Code subagents in tmux panes in detached `agents` session. Commands: `~/.config/scripts/tmux-subagents-claude`.

- [references/tools-and-models.md](references/tools-and-models.md) — model, tools, permissions
- [references/technicalities.md](references/technicalities.md) — architecture, state model, concurrency, troubleshooting

## Setup

Cleanup before/after batch:

```bash
~/.config/scripts/tmux-subagents-claude cleanup --all
```

## Workflow

1. **Spawn** all agents upfront (parallelism starts now):

   ```bash
   ~/.config/scripts/tmux-subagents-claude spawn <task> '<prompt>' [options]
   ```

2. **Wait for result** — one blocking call:

   ```bash
   ~/.config/scripts/tmux-subagents-claude result <task> --wait   # block while busy, print latest reply
   ~/.config/scripts/tmux-subagents-claude result <task>          # non-blocking; exit 1 if no reply yet
   ~/.config/scripts/tmux-subagents-claude status [--all]         # snapshot status
   ```

   `result --wait` returns latest reply once idle. `prompt … --wait` for follow-up (baselines prior, never stale). After follow-up, `result --wait` may return previous reply.

3. **Follow up / inspect / clean up:**

   ```bash
   ~/.config/scripts/tmux-subagents-claude prompt  <task> '<text>' [--wait]   # send + optionally block
   ~/.config/scripts/tmux-subagents-claude capture <task> [full|log|stop]     # raw terminal (JSONL won't do)
   ~/.config/scripts/tmux-subagents-claude cleanup <task>                     # kill one
   ~/.config/scripts/tmux-subagents-claude cleanup --all                      # kill window agents
   ~/.config/scripts/tmux-subagents-claude cleanup --prune                    # drop dead entries
   ```

## Workflow patterns

- **Agent's latest reply**: `result <task> --wait` (cheap)
- **Reply to follow-up**: `prompt <task> '…' --wait` (cheap, never stale)
- **Status across many**: `status [--all]` (cheap)
- **Done yet?**: `result <task>` (cheap, non-blocking)
- **Raw terminal**: `capture <task>` (**expensive**, debug only)

**Rules:**

- Follow-up + block: `prompt … --wait` (baselines prior). Don't use `result --wait` after `prompt` — returns prev.
- Don't background `--wait` (shell `&`): reply lost. Run foreground.
- `empty` = no reply yet. `idle` = reply ready. Neither proves latest prompt landed — confirm via reply body.
- Never `capture` `idle` agent — `result` cheaper + structured.
- Never `capture` before `prompt`. Captures debug only.
- Spawn all independent agents upfront, even if prompting later.
- `result` exit 0 = `end_turn` exists. NOT done — verify body.

## Stuck agent (INSERT mode / no response)

`prompt` resets modal state + verifies submission. Exit `prompt-not-submitted` = pane wedged. Inspect via `capture`, then cleanup + resurrect to reset + preserve context.

## Spawn options

- `--model MODEL`: e.g. `claude-opus-4-7`, `claude-sonnet-4-6`
- `--tools TOOLS`: comma-separated tools, e.g. `Read,Edit,Bash`
- `--effort LEVEL`: `low`, `medium`, `high`, `xhigh`, `max`, `auto`
- `--dangerously-skip-permissions`: skip permission prompts (user explicit only)

See [tools-and-models.md](references/tools-and-models.md) for model/tools per task.

## Resurrect

Restore killed agent + full context:

```bash
~/.config/scripts/tmux-subagents-claude resurrect <task> <session-uuid>
```

Session ID from original spawn output or prior `status` call. Creates new pane, resumes exact conversation (JSONL history preserved). Use after `cleanup <task>` to recover without losing work.

## Other commands

- `<cmd> --help` — full options

## Status values

- `empty`: live, no reply yet
- `idle`: live, reply ready
- `busy`: working
- `starting`: pane live, status pending
- `dead`: pane gone (run `cleanup --prune`)

`empty` = no completed reply. `idle` = reply in JSONL. Neither proves latest prompt landed — use `prompt … --wait` to confirm.

## Rules of thumb

- Reference agents by **task name** (unique per window).
- Block for reply: `result --wait` / `prompt --wait`. `result` > `capture`. `status` free.
- `cleanup --all` = current window only. `--prune` = cross-window, preserves live agents.

