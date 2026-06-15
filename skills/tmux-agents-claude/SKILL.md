---
name: tmux-agents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the agents session window that mirrors the current main-session window name.
---

# Tmux Agents — Claude

Spawn, monitor, and collect results from Claude Code subagents. Each subagent runs as a **pane** inside `agents:<current-window>`, keeping all agents visible in one place.

All operations go through `scripts/agent.py`.

## Help

```bash
./scripts/agent.py --help                  # list all subcommands
./scripts/agent.py spawn --help            # options for spawn
./scripts/agent.py result --help           # options for result
./scripts/agent.py capture --help          # options for capture
./scripts/agent.py cleanup --help          # options for cleanup
./scripts/agent.py resurrect --help        # options for resurrect
```

## Session Layout

- **main** — your interactive session (e.g. window `pi`)
- **agents:pi** — your agents window; each subagent is a pane within it
- Panes are named by task so you can reference them by name

## Spawn a Subagent

```bash
./scripts/agent.py spawn <task-name> '<prompt>' [options]
# Spawned 'deploy-api' in pane %42 (agents:pi) [session: e9c0307e-...]
```

Spawns a new pane, names it, writes a JSON state file, tiles the layout, and starts `claude --session-id`.
Call multiple times to run agents in parallel.

| Option | Description |
|--------|-------------|
| `--model MODEL` | Use a specific model (e.g. `claude-opus-4-7`, `claude-sonnet-4-6`) |
| `--tools TOOLS` | Comma-separated allowed tools passed via `--allowedTools` (e.g. `Read,Edit,Bash`) |
| `--effort LEVEL` | Thinking effort: `low`, `medium`, `high`, `xhigh`, `max`, `auto` |

```bash
./scripts/agent.py spawn researcher 'audit the API' \
  --model claude-opus-4-7 \
  --dangerously-skip-permissions \
  --tools 'Read,Write,Edit,Bash,Grep,Glob,WebFetch,WebSearch,Agent'
```

Common tool names: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `WebFetch`, `WebSearch`, `LSP`, `NotebookEdit`, `Skill`, `TaskCreate`, `TaskUpdate`, `TaskList`

Available models:

| Model | `--model` value |
|-------|-----------------|
| Opus 4.7 | `claude-opus-4-7` |
| Opus 4.5 | `claude-opus-4-5` |
| Sonnet 4.6 | `claude-sonnet-4-6` |
| Sonnet 4.5 | `claude-sonnet-4-5` |
| Haiku 4.5 | `claude-haiku-4-5-20251001` |

## List Panes

```bash
./scripts/agent.py status   # list pane IDs and titles in current agents window
```

## Read Result (token-efficient)

Reads the final assistant response directly from the structured JSONL log — no terminal capture overhead.

```bash
./scripts/agent.py result <task-name>          # print last complete response; exit 1 if not done yet
./scripts/agent.py result <task-name> --wait   # block until response arrives, then print it
```

## Check If Response Is Ready

Lightweight poll — reads only timestamps, never loads response text. Use this in a loop instead of calling `result` repeatedly.

```bash
./scripts/agent.py ping
```

Prints a table of all sessions in the current window:

```
SESSION-ID                            TASK      STATUS
------------------------------------  --------  -------
3f2a1b4c-...                          research  ready
9d0e7f8a-...                          writer    thinking
```

`ready` means a new response has arrived since the last `spawn` or `prompt`. Call `result <task>` once its row shows `ready`.

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

## Capture Pane Output

```bash
./scripts/agent.py capture <task-name>         # last screenful
./scripts/agent.py capture <task-name> full    # scrollback up to 3000 lines
./scripts/agent.py capture <task-name> log     # stream output to /tmp/<task-name>.log
./scripts/agent.py capture <task-name> stop    # stop streaming
```

## Resolve Pane ID

```bash
./scripts/agent.py pane-id <task-name>   # prints the tmux pane ID (e.g. %42)
```

## Resolve Session ID

Use this when the main agent's context is clear and you need the UUID to pass to `./scripts/agent.py resurrect`, share with another agent, or reference the JSONL log directly.

```bash
./scripts/agent.py session-id <task-name>   # prints the Claude session UUID
```
