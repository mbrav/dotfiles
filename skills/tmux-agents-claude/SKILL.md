---
name: tmux-agents-claude
description: Orchestrate Claude Code subagents via tmux panes. Use when you need to spawn parallel Claude agents for subtasks, delegate work, monitor running agents, read their output, or clean up finished panes. Each subagent runs in a named pane inside the agents session window that mirrors the current main-session window name.
---

# Tmux Agents — Claude

Spawn, monitor, and collect results from Claude Code subagents. Each subagent runs as a **pane** inside `agents:<current-window>`, keeping all agents visible in one place.

All operations go through `scripts/agent.py`.

## Initialization

Run `cleanup --all` before spawning agents and after they finish to remove this
window's panes and its state file:

```bash
./scripts/agent.py cleanup --all
```

> [!note] Prerequisite: `automatic-rename off`
> The skill keys everything off the **window name**, so window names must be
> stable. Set `set -g automatic-rename off` in tmux.conf (already configured in
> this dotfiles repo). Windows are named manually via `tmux-new-window.sh` /
> `tmux-rename-window.sh`, which de-dupe names via the shared
> `dedup_window_name` helper in `~/.config/scripts/_util`.

## Session Layout

- **main** — your interactive session (e.g. window `obsidian`)
- **agents** — a session with one window **per source window, named identically**
  (`agents:obsidian`); each subagent is a pane within it
- Agents are tracked by task name in the window's state file, so you reference them by task
- **Prefix+a** (tmux binding) jumps to the agents window mirroring your current
  window — same naming convention as `tmux-named-session.sh`
- A hidden **`__keeper__`** window (running a long `sleep`) anchors the agents
  session

> [!note] Keeper window keeps the session alive
> The agents session is **detached**, so if its last window's pane process exits
> (claude crashing, the sandbox suspending/resuming and killing processes, or an
> agent simply finishing), tmux would close that window and then destroy the
> whole empty session — making every subsequent `ping`/`result`/`capture`/
> `cleanup` fail with `no sessions` / `can't find window: agents`. To prevent
> this, `spawn`/`resurrect` always ensure a persistent `__keeper__` window
> exists. Dead agents then show up as `dead` in `ping` (clear `cleanup --all`)
> and can be brought back with `resurrect`, instead of vanishing silently.

> [!note] State: one JSON per window, keyed by window name
> All agents for a source window live in a **single** file
> `/tmp/tmux-claude-<window>.json`:
>
> ```json
> {
>   "window": "obsidian",
>   "agents_window_id": "@72",
>   "agents": {
>     "test-1": {"pane_id": "%134", "session_id": "...", "cwd": "..."}
>   }
> }
> ```
>
> The window NAME is resolved **focus-independently** by walking this process's
> ancestor PIDs and matching tmux's per-pane `#{pane_pid}` (falling back to
> `$TMUX_PANE`, then an untargeted query). An untargeted `display-message` alone
> follows the user's *focus* and drifts between calls — the original source of
> `no sessions` / `pane not found`.

> [!warning] Concurrent orchestrator sessions
> Multiple `pi` sessions run agents in parallel safely **as long as each lives in
> a different tmux window** (window names are unique + stable). `cleanup --all`
> only touches the **current** window. The cross-window sweep lives behind
> `cleanup --prune`, which removes **only dead-pane entries** and empty files —
> never live agents. Two orchestrators sharing one window share the
> `tmux-claude-<window>.json` namespace, so avoid duplicate task names there.

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

## Read Result (token-efficient)

Reads the final assistant response directly from the structured JSONL log — no terminal capture overhead.

```bash
./scripts/agent.py result <task-name>          # print last complete response; exit 1 if not done yet
./scripts/agent.py result <task-name> --wait   # block until response arrives, then print it
```

## Check Status / List Panes

Shows pane IDs, task names, session IDs, and ready/thinking/dead status. Use instead of calling `result` repeatedly.

```bash
./scripts/agent.py ping
```

```
PANE  TASK      SESSION-ID                            STATUS
----  --------  ------------------------------------  ------
%23   research  3f2a1b4c-...                          idle
%24   writer    9d0e7f8a-...                          busy
```

`idle` — waiting for input. `busy` — actively processing. `starting` — pane is live but the session hasn't reported status yet. `dead` — pane is gone; run `cleanup --prune` to clear its entry.
Call `result <task>` once its row shows `idle`. Use `ping --all` to list agents across every window.

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
./scripts/agent.py cleanup <task-name>   # kill one pane, drop it from this window's state
./scripts/agent.py cleanup --all         # kill this window's agents + remove its state file
./scripts/agent.py cleanup --prune       # cross-window sweep: drop dead-pane entries + empty files
```

`--all` is scoped to the current window and is concurrency-safe. `--prune` is the
only command that touches other windows, and it only removes entries whose pane
is confirmed dead — so it never deletes another live session's agents.

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

## Help

```bash
./scripts/agent.py --help                  # list all subcommands
./scripts/agent.py spawn --help            # options for spawn
./scripts/agent.py result --help           # options for result
./scripts/agent.py capture --help          # options for capture
./scripts/agent.py cleanup --help          # options for cleanup
./scripts/agent.py resurrect --help        # options for resurrect
```
