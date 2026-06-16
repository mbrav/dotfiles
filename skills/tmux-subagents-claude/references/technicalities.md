# Tmux Agents — Technicalities

Architecture and internals behind [SKILL.md](../SKILL.md). For choosing models,
tools, and `--dangerously-skip-permissions` when spawning, see
[tools-and-models.md](tools-and-models.md). All commands via `~/.config/scripts/tmux-agents-claude`.

## Session layout

- **main** — interactive session (e.g. window `obsidian`).
- **agents** — detached session; one window per source window, named identically (`agents:obsidian`). Each subagent is a pane.
- **`__keeper__`** — anchor window (`exec sleep 2147483647`) keeping agents session alive.
- **Prefix+a** — jumps to agents window mirroring current window.

Agents referenced by **task name** looked up in window's state file.

## Prerequisite: `automatic-rename off`

Skill keys off **window name** — names must be stable:

```tmux
set -g automatic-rename off
```

(Already in this dotfiles repo.) Windows named manually via `tmux-new-window.sh` / `tmux-rename-window.sh`, which de-duplicate with `dedup_window_name` helper in `~/.config/scripts/_util` (appends `-2`, `-3`, … on collision).

## Window resolution (focus-independent)

`get_win()` returns **window name** of pane command runs in, anchored to `$TMUX_PANE`:

```
tmux display-message -p -t "$TMUX_PANE" '#{window_name}'
```

Anchoring to `$TMUX_PANE` makes result independent of focus. Untargeted `display-message` resolves against active window — drifts between calls — original cause of `no sessions` / `pane not found`.

## State model — one JSON per window

```
/tmp/mux-subagents-claude-<window>.json
```

```json
{
  "window": "obsidian",
  "agents_window_id": "@72",
  "agents": {
    "test-1": {"pane_id": "%134", "session_id": "<uuid>", "cwd": "<path>"}
  }
}
```

- `window` — source window name (= agents-session window name).
- `agents_window_id` — tmux window id of mirror window in `agents`.
- `agents` — map of task name → `{pane_id, session_id, cwd}`.

Window names sanitized for filename (`/`→`-`, space→`_`).

## How panes are created

- **First `spawn`** — `ensure_agents_session` creates detached `agents` session with `__keeper__` window, then creates window named after source window; initial pane hosts agent.
- **Subsequent `spawn`s** — `split-window` adds pane to same window.
- **Every spawn** — `select-layout even-horizontal` retiles into equal columns.
- Agent started with `claude --session-id <uuid>` as keystrokes; prompt typed in **after** `❯` appears (CLI arg = system prompt = idle agent).
- **`cleanup`** kills panes; window closes on last pane death. Session survives via keeper.

## Keeper window

Without anchor, last agent pane exit → window closes → tmux destroys empty session → all later `ping`/`result`/`capture`/`cleanup` fail with `no sessions` / `can't find window: agents`.

Fix: `spawn`/`resurrect` ensure persistent `__keeper__` window (`exec sleep 2147483647`). Dead agents show `dead` in `ping` (clear with `cleanup --prune`) or recoverable via `resurrect`. Keeper excluded from Dracula agent-count segment.

## Concurrency model

Multiple sessions run agents in parallel **as long as each lives in different window** (names unique + stable):

- State namespaced per window (`mux-subagents-claude-<window>.json`).
- `cleanup --all` touches **current** window only — concurrency-safe.
- `cleanup --prune` only cross-window command. Removes **only dead-pane entries** — never deletes live session's agents.
- Two orchestrators sharing one window share same namespace — avoid duplicate task names.

## Status values (`ping`)

| Status | Meaning |
|--------|---------|
| `idle` | pane live; agent waiting for input |
| `busy` | pane live; agent actively processing |
| `starting` | pane live but claude session-status file not yet appeared (brief lag) |
| `dead` | pane gone; clear with `cleanup --prune` |

Status from `~/.claude/sessions/*.json`. Live pane never reported `dead`. `result` reads last `end_turn` text from `~/.claude/projects/<cwd-slug>/<session>.jsonl`.

### `result` semantics

`result` exit 0 means *an `end_turn` message exists in the JSONL*, **not** that the agent's work is finished or correct. The agent may have responded "starting now" and gone back to thinking. Check body content, not just exit code.

`prompt --wait` improves on this: it snapshots the last response *before* sending, then blocks for a **new** `end_turn`. So you can't accidentally pick up a stale reply.

### Stuck-input bug (INSERT mode)

`send-keys -l <text>` followed by `Enter` is silently buffered if the pane is in vim/INSERT or any modal state. Status keeps reporting `idle` (from JSONL) while prompts pile up un-submitted. `cmd_prompt` mitigates by sending `Escape Escape C-u` before paste and verifying the input line is empty after Enter; on failure it exits `prompt-not-submitted` (rc=2). Recovery: `cleanup <task>` + `resurrect <task> <session-id>` (context preserved via session UUID).

## Cleanup semantics

| Command | Scope | Effect |
|---------|-------|--------|
| `cleanup <task>` | one agent | kill pane, drop from window's state |
| `cleanup --all` | current window | kill all agents, remove state file |
| `cleanup --prune` | all windows | drop dead-pane entries + empty/unreadable files |

## Models

| Model | `--model` value |
|-------|-----------------|
| Opus 4.7 | `claude-opus-4-7` |
| Opus 4.5 | `claude-opus-4-5` |
| Sonnet 4.6 | `claude-sonnet-4-6` |
| Sonnet 4.5 | `claude-sonnet-4-5` |
| Haiku 4.5 | `claude-haiku-4-5-20251001` |

Common `--tools` values: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `WebFetch`, `WebSearch`, `LSP`, `NotebookEdit`, `Skill`, `TaskCreate`, `TaskUpdate`, `TaskList`.

## Related files

- `~/.config/scripts/tmux-agents-claude` — CLI (all subcommands).
- `~/.config/tmux/agents.sh` — Dracula status segment showing live agent counts.
- `~/.config/scripts/_util` — shared bash helpers incl. `dedup_window_name`.
- `~/.config/tmux/tmux-named-session.sh` — Prefix+a navigation to agent windows.
