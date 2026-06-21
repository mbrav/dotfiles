---
name: tmux-subagents-claude
description: Orchestrate parallel Claude Code subagents in tmux panes via the `claudemux` CLI (a stdlib-Go binary on PATH). Spawns each agent as a named pane in a detached, crash-surviving `agents` session mirroring the current window. Use when delegating parallel tasks to subagents, spawning/monitoring running agents, reading replies, scoping status to the current project, sending follow-up prompts (prompt/recap/compact), resurrecting a crashed session, adopting an existing session into the roster (hire a dead session / enlist a live one), or despawning finished agents.
---
# Tmux Agents — Claude

Parallel Claude Code subagents in tmux panes. CLI: `claudemux` (Go binary on `PATH`).

- [references/tools-and-models.md](references/tools-and-models.md) — model/tools/permissions
- [references/technicalities.md](references/technicalities.md) — architecture, state, concurrency, troubleshooting

## Install

```bash
go install github.com/mbrav/dotfiles/go/claudemux@latest   # -> ~/go/bin
```

## Setup

```bash
claudemux despawn --all   # before/after batch
```

## Workflow

1. **Spawn** all agents upfront (parallelism starts immediately). Flags precede positionals:

   ```bash
   claudemux spawn [options] <task> '<prompt>'
   ```

2. **Collect results:**

   ```bash
   claudemux result --wait <task>    # block until idle, print reply
   claudemux result <task>           # non-blocking; exit 1 if no reply yet
   claudemux status                  # snapshot table (current project)
   claudemux status <task>           # bare status word — grep/script-friendly
   ```

3. **Follow up / inspect / manage:**

   ```bash
   claudemux prompt  [--wait] <task> '<text>'   # send prompt, optionally block
   claudemux recap   <task>                     # send /recap to agent
   claudemux compact <task> [description]       # send /compact to agent
   claudemux capture <task> [full|log|stop]     # raw terminal (expensive)
   claudemux hire    <session-uuid>             # adopt a DEAD session into this roster (resumes it; refuses a live one)
   claudemux enlist  <manager-dir> [task]       # run INSIDE a live session to register itself into manager-dir's roster (no resume/fork)
   claudemux dismiss <session-uuid>             # stop managing a hired/enlisted agent (kills owned pane; leaves enlisted running)
   claudemux despawn <task>                     # kill one agent
   claudemux despawn --all                      # kill all in window
   claudemux despawn --prune                    # drop dead entries
   ```

## Rules

- **Follow-up + block**: `prompt … --wait` baselines prior reply — never stale. Don't use `result --wait` after `prompt` (returns prev).
- **Don't background** `--wait` (shell `&`): reply lost. Run foreground.
- **`empty`** = no reply yet. **`idle`** = reply ready. Neither proves latest prompt landed — confirm via body.
- **`capture`** = expensive, debug only. Don't use on idle agent (`result` is cheaper); don't use before `prompt`.
- **Spawn all** independent agents upfront, even if prompting later.
- **`result` exit 0** = `end_turn` exists. NOT done — verify body.
- **`despawn --all`** = current window only. **`--prune`** = cross-window, preserves live agents.
- **`hire`** = adopt a **dead/detached** session (by UUID, e.g. from `claudeman`) into this project's roster; it resumes in the session's **own** project dir but is tracked here, so it shows in `status` (no `--all`). It **refuses a live session** (resuming would fork a new id) — a live session must register itself in place via `enlist <manager-dir>` (run from inside that session; no resume, no fork; the manager then drives it cross-window). **`dismiss`** = teardown for both: kills an owned pane, leaves an enlisted (referenced) pane running. Use `hire`/`enlist`+`dismiss` for pre-existing sessions; `spawn`/`despawn` for fresh ones.

## Stuck agent

`prompt` repaints + clears line + verifies before sending. `prompt-not-submitted` exit = pane wedged: `capture` to inspect, then `despawn` + `resurrect`. See [technicalities.md](references/technicalities.md#prompt-submission).

## Session manager

```bash
claudeman   # fzf picker: resume / delete / rename any Claude session in current project
claudeman -a  # all projects
```

## Spawn options

Flags must come **before** the `<task> <prompt>` positionals (e.g. `spawn --model M --tools T <task> '<prompt>'`).

- `--model MODEL`: `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-5`, `claude-sonnet-4-6`, `claude-sonnet-4-5`, `claude-haiku-4-5`
- `--tools TOOLS`: comma-separated, e.g. `Read,Edit,Bash`
- `--effort LEVEL`: `low`, `medium`, `high`, `xhigh`, `max`, `auto`
- `--permission-mode MODE`: `auto` (default), `acceptEdits`, `dontAsk`, `default`, `plan`. Default `auto` proceeds without prompting and avoids the "Bypass Permissions mode" warning that wedges a fresh pane.

See [tools-and-models.md](references/tools-and-models.md) for model/tools per task type.

## Resurrect

```bash
claudemux resurrect <task> <session-uuid>
```

Session ID from spawn output or `status`. Creates new pane, resumes exact conversation (JSONL preserved).

## Status values

| Value | Meaning |
|-------|---------|
| `empty` | live, no reply yet |
| `idle` | live, reply ready |
| `busy` | working |
| `waiting` | blocked on a prompt — NOT done; `result --wait` may return stale reply |
| `waiting:permission` | blocked on a permission dialog ("Do you want to proceed?") — needs a human keystroke; a detached pane can't answer. `capture` to see the command, then decline/allow or `despawn`+`resurrect` |
| `starting` | status file pending |
| `dead` | pane gone — run `despawn --prune` |

`CONTEXT` column: context-window usage from pane footer, e.g. `90.0k/1000.0k (9.0%)`. `-` = not rendered.
