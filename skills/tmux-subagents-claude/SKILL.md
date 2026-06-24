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
claudemux despawn --all && claudemux despawn --prune   # clean slate before/after batch
```

## Workflow

1. **Spawn** all agents upfront (parallelism starts immediately). Flags precede positionals:

   ```bash
   claudemux spawn [options] <task> '<prompt>'
   ```

2. **Collect results:**

   ```bash
   claudemux result --wait <task>         # block until idle, print reply
   claudemux result <task>                # non-blocking; exit 1 if no reply yet
   claudemux status                       # all transcripts for this project + roster roles
   claudemux status <task>                # bare status word — grep/script-friendly
   claudemux status --history             # include dismissed agents
   ```

3. **Follow up / inspect / manage:**

   ```bash
   claudemux prompt  [--wait] <task> '<text>'   # send prompt, optionally block
   claudemux recap   <task>                     # send /recap to agent
   claudemux compact <task> [description]       # send /compact to agent
   claudemux despawn <task>                     # soft-delete one agent (marks dismissed, kills pane)
   claudemux despawn --all                      # soft-delete all agents in window
   claudemux despawn --prune                    # hard-delete all dismissed entries
   ```

4. **Session-internal commands** (run via `!` from inside a Claude session):

   ```bash
   ! claudemux promote [name]             # register self as master of this project's roster
   ! claudemux enlist <manager-dir> [task]  # register self into manager's roster (no resume/fork)
   ```

5. **Human/shell commands** (not agent-facing):

   ```bash
   claudemux capture <task> [full|log|stop]   # raw terminal (expensive, debug only)
   claudemux hire    <session>                # adopt a DEAD session into roster (short prefix OK)
   claudemux dismiss <session>                # soft-delete by session (short prefix OK)
   claudemux resurrect <task> <session>       # re-attach a dead session to a new pane
   ```

## Rules

- **Follow-up + block**: `prompt … --wait` baselines prior reply — never stale. Don't use `result --wait` after `prompt` (returns prev).
- **Don't background** `--wait` (shell `&`): reply lost. Run foreground.
- **`empty`** = no reply yet. **`idle`** = reply ready. Neither proves latest prompt landed — confirm via body.
- **`capture`** = expensive, debug only. Don't use on idle agent (`result` is cheaper); don't use before `prompt`.
- **Spawn all** independent agents upfront, even if prompting later.
- **`result` exit 0** = `end_turn` exists. NOT done — verify body.
- **`despawn <task>`** = soft-delete (marks dismissed; hidden from `status` by default). **`--all`** = soft-delete all in window. **`--prune`** = hard-delete all dismissed entries.
- **`status`** = transcript-first: shows all sessions in `~/.claude/projects/<slug>/` with roster roles overlaid. **`status --history`** includes dismissed. Source of truth is the Claude transcript, not the state file.
- **`hire`** = adopt a **dead/detached** session into roster (resumes it; refuses live sessions — use `enlist` for those). **`dismiss`** = soft-delete by session UUID. **`promote`** = run from inside a session via `!` to set yourself as master.
- **Pane IDs are not persisted** — they are re-discovered at runtime. After a reboot, agents show their real Claude session status (busy/idle/dead), not stale pane state.

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
claudemux resurrect <task> <session>
```

`<session>` = UUID or short 8-char prefix from `status` SESSION column. Creates new pane, resumes exact conversation (JSONL preserved). Use when a session is `dead` but you want to re-attach it to a pane.

## Status values

| Value | Meaning |
|-------|---------|
| `empty` | live, no reply yet |
| `idle` | live, reply ready |
| `busy` | working |
| `waiting` | blocked on a prompt — NOT done; `result --wait` may return stale reply |
| `waiting:permission` | blocked on a permission dialog — needs a human keystroke; `capture` to inspect, then decline/allow or `despawn`+`resurrect` |
| `starting` | status file pending |
| `dead` | no live session — `resurrect` to re-attach |

`TASK` column: task-name for active agents, `~task` for dismissed, `<untracked>` for sessions not in the roster. Dismissed entries hidden by default — use `status --history` to show them.
