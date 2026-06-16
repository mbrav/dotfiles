---
name: tmux-subagents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the detached agents session window that mirrors the current window name.
---

# Tmux Agents — Claude

Spawn and manage parallel Claude Code subagents, each in its own tmux **pane**
inside the detached `agents` session. All commands go through `~/.config/scripts/tmux-agents-claude`.

- [references/tools-and-models.md](references/tools-and-models.md) — which model,
  tools, and permissions to pass when spawning (read before choosing options).
- [references/technicalities.md](references/technicalities.md) — architecture,
  state model, concurrency rules, troubleshooting.

## Setup

Run cleanup before and after a batch of agents:

```bash
~/.config/scripts/tmux-agents-claude cleanup --all
```

## Workflow

1. **Spawn** all independent agents **upfront** (parallelism window starts now, not later) — run `spawn` multiple times:

   ```bash
   ~/.config/scripts/tmux-agents-claude spawn <task> '<prompt>' [options]
   ```

2. **Wait for the result** — default to a single blocking call, not a ping loop:

   ```bash
   ~/.config/scripts/tmux-agents-claude result <task> --wait   # block until end_turn (cheap; reads JSONL)
   ~/.config/scripts/tmux-agents-claude result <task>          # non-blocking; exit 1 if not done
   ~/.config/scripts/tmux-agents-claude ping [--all]           # snapshot status of many at once
   ```

3. **Follow up / inspect / clean up:**

   ```bash
   ~/.config/scripts/tmux-agents-claude prompt  <task> '<text>' [--wait]   # send + (optionally) block for new response
   ~/.config/scripts/tmux-agents-claude capture <task> [full|log|stop]     # raw terminal — ONLY when JSONL won't do
   ~/.config/scripts/tmux-agents-claude cleanup <task>                     # kill one
   ~/.config/scripts/tmux-agents-claude cleanup --all                      # kill this window's agents
   ~/.config/scripts/tmux-agents-claude cleanup --prune                    # drop dead entries everywhere
   ```

## Workflow patterns — pick the cheap path

| Want | Use | Cost |
|------|-----|------|
| Block until done | `result <task> --wait` | cheap (one call, reads JSONL) |
| Send + block for new reply | `prompt <task> '…' --wait` | cheap |
| Status across many | `ping [--all]` once | cheap |
| Is it done yet (non-blocking)? | `result <task>` | cheap |
| Raw terminal (debug only) | `capture <task>` | **expensive**, use only on anomaly |

**Rules:**

- After `prompt`, default to `result --wait` (or `prompt … --wait`), **not** a ping loop.
- Never `capture` an `idle` agent — `result` is cheaper and structured.
- Never `capture` before a `prompt` (pre-flight checks return useless `idle`). Captures are post-mortems.
- Don't ping a `busy` agent more than once per ~10s — it changes nothing. The tool will warn you.
- Spawn all independent agents at the start of the task, even if you'll `prompt` them later.
- `result` exit 0 = a `end_turn` message exists. NOT "work is finished" — verify body content.

## Stuck agent (INSERT mode / no response)

`prompt` resets modal state and verifies submission. If it exits with `prompt-not-submitted`,
the pane is wedged (e.g. left in vim/INSERT). Inspect with `capture`, then `cleanup <task>` +
`resurrect <task> <session-id>` to reset while preserving context.

## Spawn options

| Option | Description |
|--------|-------------|
| `--model MODEL` | e.g. `claude-opus-4-7`, `claude-sonnet-4-6` |
| `--tools TOOLS` | comma-separated allowed tools, e.g. `Read,Edit,Bash` |
| `--effort LEVEL` | `low`, `medium`, `high`, `xhigh`, `max`, `auto` |
| `--dangerously-skip-permissions` | skip permission prompts — **only when the user explicitly asks** |

See [tools-and-models.md](references/tools-and-models.md) for choosing the right
model/tools per task and the full model list.

## Other commands

- `resurrect <task> <session-uuid>` — restore a cleaned-up agent (resumes its context)
- `<cmd> --help` — full options for any subcommand

## Status values

`idle` ready · `busy` working · `starting` pane live, status pending ·
`dead` pane gone (run `cleanup --prune`)

## Rules of thumb

- Reference agents by **task name**; task names must be unique within a window.
- Prefer `result --wait` / `prompt --wait` over ping loops; prefer `result` over `capture`.
- `cleanup --all` only touches the current window; `--prune` is the only
  cross-window command and never removes live agents.
