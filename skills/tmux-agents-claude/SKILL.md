---
name: tmux-agents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the detached agents session window that mirrors the current window name.
---

# Tmux Agents — Claude

Spawn and manage parallel Claude Code subagents, each in its own tmux **pane**
inside the detached `agents` session. All commands go through `scripts/agent.py`.

- [references/tools-and-models.md](references/tools-and-models.md) — which model,
  tools, and permissions to pass when spawning (read before choosing options).
- [references/technicalities.md](references/technicalities.md) — architecture,
  state model, concurrency rules, troubleshooting.

## Setup

Run cleanup before and after a batch of agents:

```bash
./scripts/agent.py cleanup --all
```

## Workflow

1. **Spawn** one or more agents (run multiple times to parallelize):

   ```bash
   ./scripts/agent.py spawn <task> '<prompt>' [options]
   ```

2. **Check status** — call until the row shows `idle`:

   ```bash
   ./scripts/agent.py ping          # this window  (--all = every window)
   ```

3. **Read the result** (token-cheap; reads the JSONL log, not the terminal):

   ```bash
   ./scripts/agent.py result <task>          # exit 1 if not done yet
   ./scripts/agent.py result <task> --wait   # block until done
   ```

4. **Follow up / inspect / clean up:**

   ```bash
   ./scripts/agent.py prompt  <task> '<text>'        # send another message
   ./scripts/agent.py capture <task> [full|log|stop] # raw terminal output
   ./scripts/agent.py cleanup <task>                 # kill one
   ./scripts/agent.py cleanup --all                  # kill this window's agents
   ./scripts/agent.py cleanup --prune                # drop dead entries everywhere
   ```

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
- `pane-id <task>` / `session-id <task>` — resolve identifiers
- `<cmd> --help` — full options for any subcommand

## Status values

`idle` ready · `busy` working · `starting` pane live, status pending ·
`dead` pane gone (run `cleanup --prune`)

## Rules of thumb

- Reference agents by **task name**; task names must be unique within a window.
- Prefer `ping`/`result` over `capture` — they're cheap and structured.
- `cleanup --all` only touches the current window; `--prune` is the only
  cross-window command and never removes live agents.
