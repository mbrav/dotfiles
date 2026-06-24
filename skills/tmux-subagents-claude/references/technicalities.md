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
  "master": {"session_id": "<uuid>", "cwd": "<path>", "agent_name": "agent-obsidian"},
  "agents": {
    "test-1": {"session_id": "<uuid>", "cwd": "<path>", "agent_name": "subagent-obsidian-test-1"},
    "helper": {"session_id": "<uuid>", "cwd": "<other-repo>", "agent_name": "agent-foo", "enlisted": true},
    "old-job": {"session_id": "<uuid>", "cwd": "<path>", "agent_name": "subagent-obsidian-old-job", "dismissed_at": "2026-06-24T10:00:00Z"}
  }
}
```

- `window`: source window name (for display + agent naming)
- `master`: optional, set by `promote`/`init` — the orchestrating agent
- `agents`: task name → `{session_id, cwd, agent_name[, enlisted][, dismissed_at]}`
- **`pane_id` is NOT persisted** — tmux panes are ephemeral (gone after reboot).
  Pane IDs are held in memory only and re-discovered at runtime via `findPaneForSession`
  (walks `~/.claude/sessions/<pid>.json` → ppid chain → tmux pane pid).
- `enlisted` (optional): set by `enlist` — agent is **referenced in place**, not
  owned. Manager drives its pane but must never kill it on `despawn`/`dismiss`.
- `dismissed_at` (optional): timestamp set by `despawn <task>` or `dismiss`. Entry
  stays in state for history; hidden from `status` by default. `despawn --prune`
  removes all dismissed entries.

A hired agent's `cwd` may point at *another* repo while living in this project's
roster — intentional. Per-project files each carrying a `master` + `agents` form a
forest: a hired worker that runs `init`/`promote` in its own project becomes a
master of its own sub-roster.

## How panes are created

- **First spawn**: `ensure_agents_session` creates detached `agents` + `__keeper__`, then mirror window
- **Subsequent spawns**: `split-window` adds pane to same window
- **Every spawn**: `select-layout tiled` retiles, then `redrawWindowPanes` repaints (see below)
- Agent started with `claude --session-id <uuid>`, prompt typed after `❯` (CLI arg = system prompt = idle)
- **Despawn**: kill panes; window closes on last death. Session survives via keeper.

## Redraw / stuck window size

`redraw` (also run after every spawn/resurrect) repaints all panes: Claude's TUI (v2.1.x) only reflows on a **width** SIGWINCH, so a layout change leaves neighbors showing stale, wrong-width frames that bleed across borders.

`redrawWindowPanes` does `resize-window -A` (snap to the window's *automatic* size), then a one-column nudge + `-A` again to guarantee a SIGWINCH cycle. The `-A` matters: under `window-size latest` + `aggressive-resize on`, a window can get stuck at a phantom size — typically left by a transient **`display-popup`** client that attached at its own geometry then detached — and a manual `-x <width>` nudge is clamped/overridden, never escaping it. `-A` asks tmux for the size the current client actually wants. **Avoid viewing `agents` through a popup**; attach in a real window. If a window looks garbled, run `claudemux redraw`.

## Keeper window

Without anchor: last pane exit → window closes → session destroyed → `status`/`result`/`capture` fail.

Fix: persistent `__keeper__` window running `exec tail -n +1 -F <logpath>` — `tail -F` never exits (so the session never empties) and doubles as a live log view when attached. Dead agents show `dead` (clear with `despawn --prune`) or recover via `resurrect`.

## Concurrency model

Parallel agents as long as each in different window (unique + stable names):

- State per window (`~/.local/share/claudemux/<window>.json`)
- `despawn --all` = current window only (safe)
- `despawn --prune` = cross-window, removes only dead panes (preserves live)
- Shared window = shared namespace (avoid duplicate task names)

## Status values (`status`)

- `empty`: pane live, no reply yet (fresh/awaiting first prompt)
- `idle`: pane live, reply ready
- `busy`: pane live, working
- `waiting`: blocked on a prompt (permission/question). NOT done — `result --wait` may return a stale prior reply; inspect via `capture`.
- `waiting:permission`: `waiting` refined by one `capture-pane` when Claude's permission dialog ("Do you want to proceed?" + "Esc to cancel" footer) is detected. The JSONL can't reveal this — a permission-gated `tool_use` is **not flushed to the transcript while pending**, so the transcript just freezes at the last completed `tool_result`. Only `~/.claude/sessions/*.json` knows it's `waiting`; the pane snapshot classifies the dialog. Needs a human keystroke (detached pane can't answer).
- `starting`: pane live, session-status file pending
- `dead`: pane gone (clear with `despawn --prune`)

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

Recover a wedged pane: `despawn <task>` + `resurrect <task> <session-id>`.

### `status` CONTEXT column

`status` parses each live pane's footer for context-window usage (`_pane_context` → regex `\d+(\.\d+)?k/\d+(\.\d+)?k (\d+(\.\d+)?%)`), e.g. `90.0k/1000.0k (9.0%)`. `-` if pane dead/starting or footer not rendered. Costs one `capture-pane` per live pane.

## Context management commands

- `recap <task>`: sends `/recap` to the agent pane — prompts a summary of work done so far
- `compact <task> [description]`: sends `/compact [description]` — triggers Claude's context compaction with optional description

Both use `_send_prompt` (force-redraw + verify), same hardening as `prompt`.

## Despawn semantics

- `despawn <task>`: kill pane (if found) + **soft-delete** (stamps `dismissed_at`).
  Entry stays in state but is hidden from `status`. An **enlisted** agent is not
  killed; only soft-deleted.
- `despawn --all`: soft-delete all agents in the window (kills owned panes).
- `despawn --prune`: **hard-delete** all entries with `dismissed_at` set (across all
  projects). Does not delete non-dismissed entries, even if session is dead.

## Master & roster (`promote` / `init` / `hire` / `enlist` / `dismiss`)

- `promote [name]`: **preferred** way to register the current session as `master`.
  Run via `! claudemux promote` inside the Claude session. Reads
  `$CLAUDE_CODE_SESSION_ID` (set by Claude Code for `!` commands) and `$TMUX_PANE`;
  writes `master` to state without spawning anything. Optional `name` overrides the
  stored `agent_name` (default: `"master"`).

- `init [--model M] [--tools T] [--effort L] [--permission-mode P] [session-id]`:
  legacy master registration.
  - **No `session-id`** → **spawn a fresh master**: split pane in the current window.
  - **With `session-id`** → **adopt** an existing session as master (no new pane).
- `hire <session-id>`: adopt a **non-live** (dead/detached) session (by UUID) into
  this project's roster. Resumes it in a pane in the session's **original** project
  dir (recovered via `sessionCWD`) but tracks it here, so it appears in `status`
  (no `--all`) even with a foreign `cwd`. Internally shares the `resurrect` core.
  The roster task (and stored `agent_name`) come from the session's **own name** —
  the live `~/.claude/sessions/*.json` `name`, else the transcript `custom-title`
  (same source as claudeman's NAME column), falling back to `hired-<sid[:8]>` when
  unnamed. One argument is all it needs (no positional-order trap with
  `resurrect`).
  - **Live-aware**: `claude --resume` only reattaches with the same id when the
    session is *not* running; resuming a **live** session makes Claude **fork a new
    id** (the manager would then track the fork). So `hire` checks `sessionIsLive`
    (matches the session file, probes its pid with signal 0) and **refuses** a live
    session, pointing it at `enlist` instead.
- `enlist <manager-dir> [task]`: the forkless adopt for a **live** session. Run
  **from inside** the agent being managed (e.g. when a manager asks it to join):
  it records that session's own `$TMUX_PANE` + `$CLAUDE_CODE_SESSION_ID` into the
  manager's roster with `"enlisted": true` — **no resume, no new pane, no fork**.
  The agent keeps running where it is; the manager drives it cross-window via the
  server-global pane id (same primitive as `init`-adopt). `manager-dir` is the
  manager's repo path (not the slug key — paths are dash-safe under std `flag`,
  while keys start with `-`); `projectKeyForDir` resolves it to the manager's key.
  The manager reads its own path from its cwd, or its key from the `project:`
  header of `status`. Task defaults to the session's name (as `hire`); optional
  positional overrides it. The manager must already exist (have run `init` /
  spawned) or enlist errors. *(Not in SKILL.md — it is the worker's bootstrap into
  a manager, the peer of `init`.)*
- `dismiss <session-id>`: the teardown of `hire`/`enlist` — removes the entry
  (located by session UUID; current project first, then all project files). For an
  owned (hired/spawned) agent it **kills** the pane; for an **enlisted** agent it
  leaves the pane **running** (the manager only referenced it). `spawn`/`despawn`
  are the fresh-session pair; `hire`+`enlist`/`dismiss` the pre-existing-session
  pair.

## Status scoping

`status` (no `--all`) is **transcript-first**: scans all `*.jsonl` files in
`~/.claude/projects/<key>/` (ground truth), then overlays the state file for task
names and roles. Every session ever created for this project appears — not just the
ones in the roster. Dismissed entries are hidden by default (`--history` shows them).
Untracked sessions show as `<untracked>` / role `-`.

`status --all` falls back to the roster-only view across all project state files.

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
