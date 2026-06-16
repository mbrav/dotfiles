---
name: tmux-subagents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the detached agents session window that mirrors the current window name.
---

# Tmux Agents — Claude

Spawn and manage parallel Claude Code subagents, each in its own tmux **pane**
inside the detached `agents` session. All commands go through `~/.config/scripts/tmux-subagents-claude`.

- [references/tools-and-models.md](references/tools-and-models.md) — which model,
  tools, and permissions to pass when spawning (read before choosing options).
- [references/technicalities.md](references/technicalities.md) — architecture,
  state model, concurrency rules, troubleshooting.

## Setup

Run cleanup before and after a batch of agents:

```bash
~/.config/scripts/tmux-subagents-claude cleanup --all
```

## Workflow

1. **Spawn** all independent agents **upfront** (parallelism window starts now, not later) — run `spawn` multiple times:

   ```bash
   ~/.config/scripts/tmux-subagents-claude spawn <task> '<prompt>' [options]
   ```

2. **Wait for the result** — one blocking call:

   ```bash
   ~/.config/scripts/tmux-subagents-claude result <task> --wait   # block while busy, then print the latest reply
   ~/.config/scripts/tmux-subagents-claude result <task>          # non-blocking; exit 1 if no reply yet
   ~/.config/scripts/tmux-subagents-claude status [--all]         # snapshot status of many at once
   ```

   `result --wait` returns the agent's **latest** completed reply once it stops being `busy`. To send a follow-up and block for the reply *to that prompt*, use `prompt … --wait` (step 3) — it baselines the prior reply first, so it can't hand you a stale one. After a follow-up `prompt`, `result --wait` may still return the *previous* reply.

3. **Follow up / inspect / clean up:**

   ```bash
   ~/.config/scripts/tmux-subagents-claude prompt  <task> '<text>' [--wait]   # send + (optionally) block for new response
   ~/.config/scripts/tmux-subagents-claude capture <task> [full|log|stop]     # raw terminal — ONLY when JSONL won't do
   ~/.config/scripts/tmux-subagents-claude cleanup <task>                     # kill one
   ~/.config/scripts/tmux-subagents-claude cleanup --all                      # kill this window's agents
   ~/.config/scripts/tmux-subagents-claude cleanup --prune                    # drop dead entries everywhere
   ```

## Workflow patterns — pick the cheap path

| Want | Use | Cost |
|------|-----|------|
| Wait for an agent's latest reply | `result <task> --wait` | cheap (blocks while `busy`) |
| Send + block for the reply *to that prompt* | `prompt <task> '…' --wait` | cheap (baselines — never stale) |
| Status across many | `status [--all]` | cheap |
| Is it done yet (non-blocking)? | `result <task>` | cheap |
| Raw terminal (debug only) | `capture <task>` | **expensive**, use only on anomaly |

**Rules:**

- To send a follow-up and block for *its* reply, use `prompt … --wait` (it baselines the prior reply). **Don't** follow a `prompt` with `result --wait` expecting the new answer — `result` returns the latest reply, which after a follow-up may still be the previous one.
- Don't background a `--wait` call (shell `&` or a `run_in_background` Bash task): the fresh reply is then captured by the detached job instead of returned to you, so you end up chasing it via `status`/`capture`. Run `prompt … --wait` in the foreground.
- A never-yet-replied agent shows `empty`, not `idle`, so `idle` always means "a reply exists to read". But neither proves your *latest* prompt landed: a fast agent (e.g. Haiku) returns to `idle` within seconds of finishing and stays `idle` whether or not it picked up your new prompt. Confirm delivery via the reply body (`prompt … --wait`).
- Never `capture` an `idle` agent — `result` is cheaper and structured.
- Never `capture` before a `prompt` (pre-flight checks return useless `idle`). Captures are post-mortems.
- Spawn all independent agents at the start of the task, even if you'll `prompt` them later.
- `result` exit 0 = an `end_turn` message exists. NOT "work is finished" — verify body content.

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

`empty` live, no reply yet · `idle` live, reply ready to read · `busy` working ·
`starting` pane live, status pending · `dead` pane gone (run `cleanup --prune`)

`empty` vs `idle` resolves the common "idle trap": `empty` means the agent has produced **no** completed reply yet (fresh, or awaiting its first prompt), while `idle` means a completed reply is waiting in the JSONL. Neither status proves your *latest* prompt was delivered — an agent that already replied once stays `idle` whether or not it picked up a new prompt. For that, block with `prompt … --wait`.

## Rules of thumb

- Reference agents by **task name**; task names must be unique within a window.
- To block for a reply, use `result --wait` / `prompt --wait`; prefer `result` over `capture`. `status` is a free, on-demand snapshot.
- `cleanup --all` only touches the current window; `--prune` is the only
  cross-window command and never removes live agents.
