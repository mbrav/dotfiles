---
name: tmux-agents-codex
description: Orchestrate OpenAI Codex subagents via tmux panes. Use when you need to spawn parallel Codex agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the agents session window that mirrors the current main-session window name.
---

# Tmux Agents - Codex

Spawn, monitor, and collect results from Codex subagents. Each subagent runs as a **pane** inside `agents:<current-window>`, keeping all agents visible in one place.

## Session Layout

- **main** — your interactive session (e.g. window `pi`)
- **agents:pi** — your agents window; each subagent is a pane within it
- Panes are named by task so you can reference them by name

## Spawn a Subagent

```bash
./scripts/spawn.sh <task-name> '<prompt>'
# Prints the pane ID on success, e.g.: Spawned 'deploy-api' in pane %42 (agents:pi)
```

Spawns a new pane, names it, stores the pane ID, applies tiled layout, and starts Codex.
Call multiple times to run agents in parallel.

## Check Status

```bash
./scripts/status.sh                  # list all panes in current agents window
./scripts/status.sh <task-name>      # "running (codex)" or "done"
```

## Read Output

```bash
./scripts/capture.sh <task-name>           # last screenful
./scripts/capture.sh <task-name> full      # full scrollback (~3000 lines)
./scripts/capture.sh <task-name> log       # stream to /tmp/<task-name>.log
./scripts/capture.sh <task-name> stop      # stop streaming
```

## Send Follow-Up

```bash
./scripts/send.sh <task-name> '<text>'
```

## Cleanup

```bash
./scripts/cleanup.sh <task-name>     # kill one pane
./scripts/cleanup.sh --all           # kill all agent panes (keep base pane)
```
