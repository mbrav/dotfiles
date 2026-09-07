---
name: herdr
description: Orchestrate parallel Claude Code subagents as sibling panes in the CURRENT herdr tab, via the bundled herd.sh wrapper over the `herdr` CLI. Use to delegate parallel tasks, spawn/monitor agents, read replies, send follow-up prompts, wait on state, and close finished agents. Requires HERDR_ENV=1 (running inside a herdr-managed pane).
---
# Herdr

Spawn Claude Code subagents as **sibling panes in the current tab** (no popup window, no new workspace/tab). Driver: [`herd.sh`](herd.sh) — a thin bash wrapper over `herdr` that does all the JSON parsing. `herdr --skill` is the authoritative command reference; this skill is the opinionated same-tab workflow on top of it.

## Gate

Only works inside a herdr pane. First line of every session:

```bash
test "${HERDR_ENV:-}" = 1 || echo "not in herdr — stop"
```

`herd.sh` (bundled next to this file) enforces this itself. Commands below call it as `herd.sh` — invoke it by its path in this skill's directory (`.claude/skills/herdr/herd.sh` where the skill is installed). No PATH entry or install needed; it's a plain bash script.

## Workflow

1. **Spawn** all agents upfront (parallelism starts immediately):

   ```bash
   herd.sh spawn <name>                                  # split current tab, start idle claude
   herd.sh spawn <name> 'do X' --model claude-opus-4-8   # start + fire prompt, no wait (fan out)
   herd.sh spawn <name> 'do X' --dir /path/to/repo       # different cwd (default: current $PWD)
   ```

   Default model `claude-haiku-4-5`. Names: `[a-z][a-z0-9_-]{0,31}`, unique among live agents.

2. **Collect** (blocking, one at a time):

   ```bash
   herd.sh ask <name> 'prompt'      # submit, block until settled, print reply
   herd.sh wait <name> [ms]         # block until idle/done/blocked, print status word
   herd.sh reply <name> [lines]     # re-read last output (recent-unwrapped)
   herd.sh status <name>            # bare status word (grep-friendly)
   herd.sh ls                       # all agents: pane_id  status  title
   ```

3. **Teardown:**

   ```bash
   herd.sh kill <name>              # close that agent's pane
   ```

Fan-out pattern: `spawn a 'task A'; spawn b 'task B'; spawn c 'task C'` — then `ask`/`wait` each. All three panes tile in the one tab.

## Rules

- **Spawn all** independent agents first, prompt/collect after — that is the parallelism.
- **`--wait` blocks** on the first settled `idle`/`done`/`blocked`. Never background it (`&`) — reply is lost.
- **First prompt to a fresh agent can trip herdr's 5 s stall guard** (`agent_prompt_stalled`). `ask` auto-retries once; a bare `herdr agent prompt` does not — retry it yourself.
- **`blocked`** = agent hit an approval/question UI. NOT done. Inspect with `herd.sh reply <name>`, then answer keys via `herdr agent send-keys <name> 1` (or `esc`, `ctrl+c`). Do not auto-answer approval dialogs — surface to the user.
- **`done` vs `idle`**: same idle state; `done` = finished background work the focused UI hasn't seen. CLI reads don't mark seen. Both mean ready.
- **`unknown`** ≠ complete — herdr sees an agent it can't classify (e.g. non-Claude, or mid-startup).
- **Splits auto-pick direction** (down when ≤3 panes, else right) to avoid unusable slivers. Force layout with raw `herdr pane split` if needed.
- **Never close panes/tabs you did not spawn.** `kill` only your own agents. Never `herdr server stop`.
- Keeps user focus in the caller pane (`--no-focus`) and preserves cwd.

## Gotchas

- **Long replies truncate.** Claude renders on the terminal alt-screen; rows scrolled off don't reach herdr scrollback, so `reply --lines 500` can't recover them. Fallback: prompt the agent to write its full answer to a temp `.md` and reply only the path, then read the file.
- **`read` sources**: `recent-unwrapped` (default here — joins soft wraps, best for transcripts) · `visible` · `recent` · `detection`. Add `--format ansi` only when color is evidence.
- **Agent name follows the pane occupant** and clears when the agent exits — a killed/exited name is free to reuse.
- **Native Claude flags** pass after `--` in spawn (the wrapper forwards `--model`; edit `herd.sh` to forward more, e.g. `--permission-mode acceptEdits` for unattended edits — a fresh pane defaults to manual mode).
- CLI errors are JSON on stderr, exit 1; syntax errors exit 2.

## Raw escape hatch

Anything the wrapper doesn't cover, hit `herdr` directly (targets = unique agent name or pane id):

```bash
herdr agent list | ...            # full JSON
herdr agent get <name>            # one agent, incl pane_id
herdr agent send-keys <name> esc
herdr agent prompt <name> '...' --until blocked --timeout 120000
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

See `herdr --skill` and `herdr agent` / `herdr pane` for the full surface.
