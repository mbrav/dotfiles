# Tmux Agents — Technicalities

Architecture behind [SKILL.md](../SKILL.md). Model/tools selection: [tools-and-models.md](tools-and-models.md). Commands: `~/.config/scripts/tmux-subagents-claude`.

## Session layout

- **main**: interactive session (e.g., window `obsidian`)
- **agents**: detached session, one window per source window (e.g., `agents:obsidian`). Each agent = pane.
- **`__keeper__`**: anchor window (`sleep 2147483647`) keeps session alive
- **Prefix+a**: jump to mirror window

Agents referenced by task name, looked up in state file.

## Prerequisite: `automatic-rename off`

Skill keys off **window name** — names must be stable:

```tmux
set -g automatic-rename off
```

(Already in this dotfiles repo.) Windows named manually via `tmux-new-window.sh` / `tmux-rename-window.sh`, which de-duplicate with `dedup_window_name` helper in `~/.config/scripts/_util` (appends `-2`, `-3`, … on collision).

## Window resolution (focus-independent)

`get_win()` returns **window name** anchored to `$TMUX_PANE`:

```
tmux display-message -p -t "$TMUX_PANE" '#{window_name}'
```

Anchoring = independent of focus. Untargeted `display-message` drifts (causes `no sessions` / `pane not found`).

## State model — one JSON per window

```
/tmp/mux-subagents-claude-<window>.json
```

```json
{
  "window": "obsidian",
  "agents_window_id": "@72",
  "agents": {
    "test-1": {"pane_id": "%134", "session_id": "<uuid>", "cwd": "<path>", "agent_name": "subagent-obsidian-test-1"}
  }
}
```

- `window`: source window name
- `agents_window_id`: tmux window id in `agents` session
- `agents`: task name → `{pane_id, session_id, cwd, agent_name}`

Names sanitized: `/`→`-`, space→`_`.

## How panes are created

- **First spawn**: `ensure_agents_session` creates detached `agents` + `__keeper__`, then mirror window
- **Subsequent spawns**: `split-window` adds pane to same window
- **Every spawn**: `select-layout even-horizontal` retiles columns
- Agent started with `claude --session-id <uuid>`, prompt typed after `❯` (CLI arg = system prompt = idle)
- **Cleanup**: kill panes; window closes on last death. Session survives via keeper.

## Keeper window

Without anchor: last pane exit → window closes → session destroyed → `status`/`result`/`capture` fail.

Fix: persistent `__keeper__` window (`sleep 2147483647`). Dead agents show `dead` (clear with `cleanup --prune`) or recover via `resurrect`.

## Concurrency model

Parallel agents as long as each in different window (unique + stable names):

- State per window (`mux-subagents-claude-<window>.json`)
- `cleanup --all` = current window only (safe)
- `cleanup --prune` = cross-window, removes only dead panes (preserves live)
- Shared window = shared namespace (avoid duplicate task names)

## Status values (`status`)

- `empty`: pane live, no reply yet (fresh/awaiting first prompt)
- `idle`: pane live, reply ready
- `busy`: pane live, working
- `waiting`: blocked on a prompt (permission/question). NOT done — `result --wait` may return a stale prior reply; inspect via `capture`.
- `starting`: pane live, session-status file pending
- `dead`: pane gone (clear with `cleanup --prune`)

From `~/.claude/sessions/*.json`. `empty` = no `end_turn` in JSONL (separates "nothing yet" from "done"). `result` reads last `end_turn` from `~/.claude/projects/<cwd-slug>/<session>.jsonl`, where `<cwd-slug>` = cwd with every non-alphanumeric char → `-` (matches Claude's own encoding; e.g. `transcribe_audio` → `transcribe-audio`).

### `result` semantics

`result` exit 0 = `end_turn` exists, NOT done. Check body content.

`prompt --wait` snapshots prior reply, blocks for **new** `end_turn` (no stale).

`result --wait` blocks while `busy`, prints latest. Stops stale-while-working, but misses stale-after-idle. Use `prompt --wait` for guaranteed-new reply.

`empty`/`idle` split: fresh agent = `empty`. `idle` ambiguous (done or not received?). Fast models return `idle` in seconds — don't infer "dropped" from `idle`. Read reply body.

### Prompt submission

`cmd_prompt` → `_send_prompt` does, in order:

1. **`_force_redraw(pane)`** — nudge window height ±1 (`resize-window -y h-1` then `-y h`). Delivers SIGWINCH so Claude repaints full-height with its input box pinned to the bottom. Height-only: width is unchanged so text never rewraps (a width nudge reflows everything and can scroll the box out of view). Also run after `spawn`.
2. **`_reset_input_line(pane)`** — `C-u` only (kill input line). **No Escape**: in current Claude (v2.1.x) Esc-Esc opens the rewind/checkpoint modal, so the paste lands in that menu and never submits.
3. paste `-l <text>` + `Enter`.
4. **`_verify_submitted`** — capture, strip trailing blank lines, check the text is no longer on the input line; retry once, else `prompt-not-submitted` (rc=2).

Why repaint matters: Claude measures pane height at startup. When the pane later grows (layout rebalance as siblings spawn/close), Claude does NOT repaint — input box stranded mid-pane with blank lines below the footer. Pastes miss it, and a naive last-6-lines verify sees only blanks → false "submitted" → `prompt --wait` polls a reply that never comes.

Recover a wedged pane: `cleanup <task>` + `resurrect <task> <session-id>`.

### `status` CONTEXT column

`status` parses each live pane's footer for context-window usage (`_pane_context` → regex `\d+(\.\d+)?k/\d+(\.\d+)?k (\d+(\.\d+)?%)`), e.g. `90.0k/1000.0k (9.0%)`. `-` if pane dead/starting or footer not rendered. Costs one `capture-pane` per live pane.

## Cleanup semantics

- `cleanup <task>`: kill pane, drop from state
- `cleanup --all`: kill all in window, remove state file
- `cleanup --prune`: drop dead panes + empty/unreadable files (all windows)

## Models

- Opus 4.7: `claude-opus-4-7`
- Opus 4.5: `claude-opus-4-5`
- Sonnet 4.6: `claude-sonnet-4-6`
- Sonnet 4.5: `claude-sonnet-4-5`
- Haiku 4.5: `claude-haiku-4-5-20251001`

Tools: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `WebFetch`, `WebSearch`, `LSP`, `NotebookEdit`, `Skill`, `TaskCreate`, `TaskUpdate`, `TaskList`.

## Related files

- `~/.config/scripts/tmux-subagents-claude` — CLI
- `~/.config/tmux/agents.sh` — Dracula agent count segment
- `~/.config/scripts/_util` — bash helpers + `dedup_window_name`
- `~/.config/tmux/tmux-named-session.sh` — Prefix+a navigation
