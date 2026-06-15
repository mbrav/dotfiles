---
name: tmux-agents-codex
description: Orchestrate Codex subagents via tmux panes. Use when you need to spawn parallel Codex agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the agents session window that mirrors the current main-session window name.
---

# Tmux Agents — Codex

Spawn, monitor, and collect results from Codex subagents. Each subagent runs as a **pane** inside `agents:<current-window>`, keeping all agents visible in one place.

All operations go through `scripts/agent.py`.

## Session Layout

- **main** — your interactive session (e.g. window `pi`)
- **agents:pi** — your agents window; each subagent is a pane within it
- Panes are named by task so you can reference them by name

## Spawn a Subagent

```bash
./scripts/agent.py spawn <task-name> '<prompt>'
# Spawned 'deploy-api' in pane %42 (agents:pi) [session: 019ecaed-...]
```

Spawns a new pane, names it, writes a JSON state file, tiles the layout, starts `codex`, and records the session UUID plus JSONL path from the file Codex creates.
Call multiple times to run agents in parallel.

## List Panes

```bash
./scripts/agent.py status   # list pane IDs and titles in current agents window
```

## Read Result (token-efficient)

Reads the final agent response from Codex's structured JSONL log, using `task_complete.last_agent_message` instead of terminal capture.
The state file caches the JSONL path and byte offsets, so repeated checks avoid rescanning old session history.

```bash
./scripts/agent.py result <task-name>          # print fresh complete response; exit 1 if not done yet
./scripts/agent.py result <task-name> --wait   # block until fresh response arrives, then print it
```

## Check If Response Is Ready

Lightweight poll — advances from the cached byte offset and records the latest completion offset without decoding the response text. Use this in a loop instead of calling `result` repeatedly.

```bash
./scripts/agent.py ping <task-name>   # prints "ready", "thinking", or "no session"
```

`ready` means a new response has arrived since the last `spawn` or `prompt`. Call `result` once ping returns `ready`.

## Resurrect a Cleaned-Up Agent

Brings back an agent after `cleanup --all` has killed its pane. Requires the session UUID from the original `spawn` output. Opens a new pane and resumes the conversation from where it left off.

```bash
./scripts/agent.py resurrect <task-name> <session-uuid>
```

## Send Follow-Up Prompt

```bash
./scripts/agent.py prompt <task-name> '<text>'
```

Resets the ping watermark — subsequent `ping` calls will wait for the next fresh response.

## Cleanup

```bash
./scripts/agent.py cleanup <task-name>   # kill one pane
./scripts/agent.py cleanup --all         # kill all agent panes (keep base pane)
```

## Resolve Pane ID

```bash
./scripts/agent.py pane-id <task-name>   # prints the tmux pane ID (e.g. %42)
```

## Raw Terminal Capture (debugging)

```bash
./scripts/capture.sh <task-name>           # last screenful
./scripts/capture.sh <task-name> full      # full scrollback (~3000 lines)
./scripts/capture.sh <task-name> log       # stream to /tmp/<task-name>.log
./scripts/capture.sh <task-name> stop      # stop streaming
```
