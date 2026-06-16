# Tmux Agents — Technicalities

Architecture and internals behind [SKILL.md](../SKILL.md). For choosing models,
tools, and `--dangerously-skip-permissions` when spawning, see
[tools-and-models.md](tools-and-models.md). All commands via `~/.config/scripts/tmux-subagents-claude`.

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

Without anchor, last agent pane exit → window closes → tmux destroys empty session → all later `status`/`result`/`capture`/`cleanup` fail with `no sessions` / `can't find window: agents`.

Fix: `spawn`/`resurrect` ensure persistent `__keeper__` window (`exec sleep 2147483647`). Dead agents show `dead` in `status` (clear with `cleanup --prune`) or recoverable via `resurrect`. Keeper excluded from Dracula agent-count segment.

## Concurrency model

Multiple sessions run agents in parallel **as long as each lives in different window** (names unique + stable):

- State namespaced per window (`mux-subagents-claude-<window>.json`).
- `cleanup --all` touches **current** window only — concurrency-safe.
- `cleanup --prune` only cross-window command. Removes **only dead-pane entries** — never deletes live session's agents.
- Two orchestrators sharing one window share same namespace — avoid duplicate task names.

## Status values (`status`)

| Status | Meaning |
|--------|---------|
| `empty` | pane live; agent idle but no completed reply in the JSONL yet (fresh / awaiting first prompt) |
| `idle` | pane live; agent waiting for input with at least one completed reply to read |
| `busy` | pane live; agent actively processing |
| `starting` | pane live but claude session-status file not yet appeared (brief lag) |
| `dead` | pane gone; clear with `cleanup --prune` |

Status from `~/.claude/sessions/*.json`. Live pane never reported `dead`. An idle pane is refined to `empty` when `extract_last_response` finds no `end_turn` in its JSONL — this separates "nothing produced yet" from "done, output ready" (the *idle trap* that misleads orchestrators into thinking a prompt was dropped). `result` reads last `end_turn` text from `~/.claude/projects/<cwd-slug>/<session>.jsonl`.

### `result` semantics

`result` exit 0 means *an `end_turn` message exists in the JSONL*, **not** that the agent's work is finished or correct. The agent may have responded "starting now" and gone back to thinking. Check body content, not just exit code.

`prompt --wait` improves on this: it snapshots the last response *before* sending, then blocks for a **new** `end_turn`. So you can't accidentally pick up a stale reply.

`result --wait` blocks while the session status is `busy`, then prints the latest `end_turn`. This stops it returning a stale prior reply *while the agent is still working*, but it cannot detect staleness once the agent has gone back to `idle`: if you send a follow-up and the agent finishes before you call, you get that (correct, latest) reply — but in the brief window before its status flips to `busy` you could still catch the previous one. For send-and-block on a guaranteed-new reply, use `prompt --wait`.

The `empty`/`idle` split (see *Status values*) removes the worst of the idle trap: a freshly spawned agent that has produced nothing shows `empty`, not `idle`. But `idle` is still ambiguous once an agent has replied at least once — it means "waiting for input" whether the agent just *finished your latest prompt* or *never received it*. A fast model returns to `idle` within seconds, so `status` showing `idle` shortly after a `prompt` does **not** prove the prompt was dropped — read the reply body to confirm. Inferring "prompt not delivered" from `idle`, then re-sending and `capture`-ing, is the classic thrash this skill exists to prevent.

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

- `~/.config/scripts/tmux-subagents-claude` — CLI (all subcommands).
- `~/.config/tmux/agents.sh` — Dracula status segment showing live agent counts.
- `~/.config/scripts/_util` — shared bash helpers incl. `dedup_window_name`.
- `~/.config/tmux/tmux-named-session.sh` — Prefix+a navigation to agent windows.
