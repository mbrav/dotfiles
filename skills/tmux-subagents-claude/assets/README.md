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

## Full reference config

`dotfiles/.config/tmux/tmux.conf` has the full setup — Dracula theme, plugin
list, Prefix+a binding, custom segments. Use it as a template for the
polished look on top of the minimum.
