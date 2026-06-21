# Tmux Agents — Technicalities

Architecture behind [SKILL.md](../SKILL.md). Model/tools selection: [tools-and-models.md](tools-and-models.md). Commands: `claudemux` (Go binary on `PATH`; source in [`go/claudemux/`](../../../go/claudemux)).

## Session layout

- **main**: interactive session (e.g., window `obsidian`)
- **agents**: detached session, one window per source window (e.g., `agents:obsidian`). Each agent = pane.
- **`__keeper__`**: anchor window (`tail -F` the log file) keeps session alive
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

## State model — one JSON per project

The file is named with **Claude's own `~/.claude/projects/` slug convention**: the
git repo root (or cwd) with every non-alphanumeric char → `-` (`cwdToProjectDir`
applied to `projectScope(cwd)`). Every command from anywhere inside a repo
resolves to the same key, so one project has exactly one roster.

```
~/.local/share/claudemux/<project-slug>.json
    e.g.  -home-x-dev-github-com-mbrav-obsidian.json
```

```json
{
  "window": "obsidian",
  "agents_window_id": "@72",
  "master": {"pane_id": "%21", "session_id": "<uuid>", "cwd": "<path>", "agent_name": "agent-obsidian"},
  "agents": {
    "test-1": {"pane_id": "%134", "session_id": "<uuid>", "cwd": "<path>", "agent_name": "subagent-obsidian-test-1"}
  }
}
```

- `window`: source window name (the agents-session mirror window + agent naming)
- `agents_window_id`: tmux window id in `agents` session
- `master`: optional, set by `init` — the orchestrating agent (`agent-<project>`)
- `agents`: task name → `{pane_id, session_id, cwd, agent_name}`

A hired agent's `cwd` may point at *another* repo (it resumes in its own project
dir) while it lives in this project's roster — that is intentional. Per-project
files each carrying a `master` + `agents` form a forest: a hired worker that runs
`init` in its own project becomes a master of its own sub-roster.

## How panes are created

- **First spawn**: `ensure_agents_session` creates detached `agents` + `__keeper__`, then mirror window
- **Subsequent spawns**: `split-window` adds pane to same window
- **Every spawn**: `select-layout tiled` retiles, then `redrawWindowPanes` repaints (see below)
- Agent started with `claude --session-id <uuid>`, prompt typed after `❯` (CLI arg = system prompt = idle)
- **Cleanup**: kill panes; window closes on last death. Session survives via keeper.

## Redraw / stuck window size

`redraw` (also run after every spawn/resurrect) repaints all panes: Claude's TUI (v2.1.x) only reflows on a **width** SIGWINCH, so a layout change leaves neighbors showing stale, wrong-width frames that bleed across borders.

`redrawWindowPanes` does `resize-window -A` (snap to the window's *automatic* size), then a one-column nudge + `-A` again to guarantee a SIGWINCH cycle. The `-A` matters: under `window-size latest` + `aggressive-resize on`, a window can get stuck at a phantom size — typically left by a transient **`display-popup`** client that attached at its own geometry then detached — and a manual `-x <width>` nudge is clamped/overridden, never escaping it. `-A` asks tmux for the size the current client actually wants. **Avoid viewing `agents` through a popup**; attach in a real window. If a window looks garbled, run `claudemux redraw`.

## Keeper window

Without anchor: last pane exit → window closes → session destroyed → `status`/`result`/`capture` fail.

Fix: persistent `__keeper__` window running `exec tail -n +1 -F <logpath>` — `tail -F` never exits (so the session never empties) and doubles as a live log view when attached. Dead agents show `dead` (clear with `cleanup --prune`) or recover via `resurrect`.

## Concurrency model

Parallel agents as long as each in different window (unique + stable names):

- State per window (`~/.local/share/claudemux/<window>.json`)
- `cleanup --all` = current window only (safe)
- `cleanup --prune` = cross-window, removes only dead panes (preserves live)
- Shared window = shared namespace (avoid duplicate task names)

## Status values (`status`)

- `empty`: pane live, no reply yet (fresh/awaiting first prompt)
- `idle`: pane live, reply ready
- `busy`: pane live, working
- `waiting`: blocked on a prompt (permission/question). NOT done — `result --wait` may return a stale prior reply; inspect via `capture`.
- `waiting:permission`: `waiting` refined by one `capture-pane` when Claude's permission dialog ("Do you want to proceed?" + "Esc to cancel" footer) is detected. The JSONL can't reveal this — a permission-gated `tool_use` is **not flushed to the transcript while pending**, so the transcript just freezes at the last completed `tool_result`. Only `~/.claude/sessions/*.json` knows it's `waiting`; the pane snapshot classifies the dialog. Needs a human keystroke (detached pane can't answer).
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

## Context management commands

- `recap <task>`: sends `/recap` to the agent pane — prompts a summary of work done so far
- `compact <task> [description]`: sends `/compact [description]` — triggers Claude's context compaction with optional description

Both use `_send_prompt` (force-redraw + verify), same hardening as `prompt`.

## Cleanup semantics

- `cleanup <task>`: kill pane, drop from state (preserves `master` if set)
- `cleanup --all`: kill all in window, remove state file
- `cleanup --prune`: drop dead panes + empty/unreadable files (all windows)

## Master & roster (`init` / `hire` / `dismiss`)

- `init [--model M] [--tools T] [--effort L] [--permission-mode P] [session-id]`:
  register the project's `master`.
  - **No `session-id`** → **spawn a fresh master**: a split pane in the **current
    window** (beside the human, not the detached agents session) running a
    brand-new claude session (generated UUID) named `agent-<project>`. Starts idle
    (no prompt). The attached client drives the resize, so no manual redraw.
  - **With `session-id`** → **adopt an existing session** as the master (no new
    pane): records that session with the current pane (`$TMUX_PANE`) and cwd as
    `agent-<project>`. Intended for a running session to register itself, e.g.
    `init "$CLAUDE_CODE_SESSION_ID"`.

  Either way the master lives in the current window and is the orchestrator you
  work in to spawn/hire. *(Not in SKILL.md — it is the master's own bootstrap
  step.)*
- `hire <session-id>`: adopt an existing session (by UUID) into this project's
  roster. Resumes it in a pane in the session's **original** project dir
  (recovered via `sessionCWD`) but tracks it here, so it appears in `status` (no
  `--all`) even with a foreign `cwd`. Internally shares the `resurrect` core. The
  roster task (and stored `agent_name`) come from the session's **own name** —
  the live `~/.claude/sessions/*.json` `name`, else the transcript `custom-title`
  (same source as claudeman's NAME column), falling back to `hired-<sid[:8]>` when
  unnamed. One argument is all it needs (no positional-order trap with
  `resurrect`).
- `dismiss <session-id>`: the teardown of `hire` — kills the pane and removes the
  entry (located by session UUID; searches the current project first, then all
  project files). `spawn`/`cleanup` are the fresh-session pair; `hire`/`dismiss`
  the pre-existing-session pair.

## Status scoping

`status` (no `--all`) loads **only the current project's state file** and shows
every agent in it (plus the `master` row if present) — the chosen file *is* the
scope, so hired agents from other repos still appear. `status --all` iterates
every project file under `STATE_DIR`. There is no per-agent cwd filter.

## Tools

- **Files**: `Read`, `Write`, `Edit`, `Grep`, `Glob`, `NotebookEdit`
- **Shell**: `Bash`
- **Agents**: `Agent`, `Skill`
- **Web**: `WebFetch`, `WebSearch`
- **Tasks**: `TaskCreate`, `TaskUpdate`, `TaskList`
- **IDE**: `LSP`

## Implementation

Single Go binary (stdlib only), `module github.com/mbrav/dotfiles/go`, package in
`go/claudemux/`. Layered files: `config.go` (constants + env-driven
`Config` + logging), `tmux.go` (tmux primitives), `state.go` (window/state store),
`claude.go` (transcript/session readers), `session.go` (agents session + keeper +
panes), `tui.go` (the TUI driver), `agent.go` (`resolveAgent`), `status.go`
(`projectScope`/`buildRows`), `commands.go`, `main.go` (CLI). Tunable timing lives
in `Config` (env `TMUX_AGENT_*`, e.g. `TMUX_AGENT_WAIT_TIMEOUT`). Build/test:
`cd go && go test ./... && go build -o ~/go/bin/claudemux ./claudemux`.

## Related files

- `claudemux` — CLI (Go binary in `~/go/bin`); source in `go/claudemux/`
- `~/.config/tmux/agents.sh` — Dracula agent count segment
- `~/.config/scripts/_util` — bash helpers + `dedup_window_name`
- `~/.config/tmux/tmux-named-session.sh` — Prefix+a navigation
