# Assets

Reference configs for setting up `claudemux` from scratch.

## `tmux/tmux.conf`

Minimal tmux config the skill needs to work. Three layers:

| Layer | Purpose |
|-------|---------|
| **REQUIRED** | `automatic-rename off` + `allow-rename off`. Skill keys off window name; without these, tmux renames windows automatically and the `agents:<window>` mirror breaks. |
| **RECOMMENDED** | History limit, mouse, extended keys, low escape-time. Make `capture`/`prompt` more reliable. |
| **OPTIONAL** | `Prefix+a` jump to agents session, Dracula agent-count segment. Both require helper scripts from the dotfiles repo (`tmux-named-session.sh`, `agents.sh`). |

### Install

Replace `~/.tmux.conf` outright:

```bash
cp assets/tmux.conf ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

Or source it from an existing config:

```tmux
source-file ~/path/to/this/assets/tmux/tmux.conf
```

### Verify

```bash
tmux show -g automatic-rename   # must be 'off'
tmux show -g allow-rename       # must be 'off'
```

Then `claudemux spawn smoke 'say hi'` lands an
agent in the `agents` session window named after your current window.

## `statusline-command.sh` (REQUIRED for the `CONTEXT` column)

`claudemux status` does **not** read context usage from any API or JSONL — it
scrapes the rendered pane footer. `paneContext` (in `go/claudemux/tui.go`) runs
the regex

```
\d+(?:\.\d+)?k/\d+(?:\.\d+)?k\s*\(\d+(?:\.\d+)?%\)
```

over each captured pane line and takes the **last** match. So the `CONTEXT`
column (e.g. `90.0k/1000.0k (9.0%)`) only populates when each agent's Claude
status line prints that exact `used/total (pct%)` shape. Without it the column
shows `-` for every agent and you lose at-a-glance context-window tracking.

`statusline-command.sh` is the reference status line that emits a matching
token. Its context segment (the tail of the line) renders as:

```
50.0k/1000.0k (5.0%)
```

built from `.context_window.used_percentage` × `.context_window.context_window_size`.
The earlier segments (`↑`/`↓` per-call tokens, `R`/`W` cache, cost, rate-limit
and permission-mode tags) are informational and not parsed — only the
`Nk/Nk (N%)` tail matters to `claudemux`.

### Install

Point Claude Code's `statusLine` setting at the script (it reads the status-line
JSON on stdin and prints one line):

```jsonc
// ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

```bash
cp assets/statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Requires `jq` and `awk` on `PATH`. The script falls back gracefully (empty
segment) when a field is absent, so a pane that hasn't rendered usage yet just
shows `-` until the footer appears.

### Verify

Spawn an agent, let it answer once, then:

```bash
claudemux status   # the CONTEXT column should show Nk/Nk (N%), not '-'
```

## Full reference config

`dotfiles/.config/tmux/tmux.conf` has the full setup — Dracula theme, plugin
list, Prefix+a binding, custom segments. Use it as a template for the
polished look on top of the minimum.
