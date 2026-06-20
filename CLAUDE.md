# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal DevOps-oriented dotfiles for an Arch-based Linux setup (also used on macOS, branch `mac`). Shell config + a library of standalone CLI scripts. Everything is installed by **symlinking** into `$HOME`, not copying — edits in this repo take effect live in the shell.

## Install / build / run

```bash
./install.sh            # interactive symlink install (interactive)
force=1 ./install.sh    # non-interactive (used by Docker + CI)
./docker.sh             # build + run configs in an ephemeral Alpine container (WIP)
```

- `install.sh` → `dotfiles/.config/scripts/dotinstall` (symlink target). Symlinks every entry in `dotfiles/.config/*` to `~/.config/*` and every top-level file in `dotfiles/*` to `~/*`. Without `force=1` it prompts before overwriting.
- `docker.sh` → `dotfiles/.config/scripts/dotdok`. Builds image `mbrav/dotfiles:latest` from `Dockerfile` (Alpine), runs `force=1 dotinstall` inside. Flags: `-u` mount home, `-p` podman, `-n` no cache. There is no separate test suite — the Docker build *is* the smoke test for a clean install.
- `dotmodup` updates git submodules (`git submodule update --remote`).

No linter/test framework. Validate shell scripts with `shellcheck <script>` before committing.

## Submodules

Clone with `--recurse-submodules`. Two submodules (see `.gitmodules`):

- `dotfiles/.config/tmux/plugins/tpm` — tmux plugin manager
- `dotfiles/.config/scripts/kubectl-aliases` — sourced by both shells

## Architecture

**Dual-shell, single source of aliases.** Fish (`dotfiles/.config/fish/config.fish`) is primary; Bash (`dotfiles/.bashrc`) is the POSIX fallback for restricted servers. Both source the *same* files so behavior stays in sync:

- `dotfiles/.config/scripts/_aliases` — POSIX-`sh`-compatible aliases + tool env (must work in fish AND bash; guard every modern tool with `command -v <tool> >/dev/null && ...`).
- `dotfiles/.config/scripts/_secrets` — machine-local secrets/aliases. **Must never contain real credentials** (see Security below).
- `~/.config/scripts` is added to `PATH`, so every executable script there is a global command.

When adding a shell-wide alias or env var, put it in `_aliases` (not in `config.fish`/`.bashrc`) unless it is genuinely fish- or bash-specific. Anything modern-tool-dependent must degrade gracefully when the tool is absent — restricted servers may lack `eza`/`bat`/`fd`/etc.

**Scripts library** (`dotfiles/.config/scripts/`) — standalone executables, each becomes a PATH command. Shared conventions:

- `source "${script_dir}/_util"` for colored output + prompts: `error_msg`/`warning_msg`/`success_msg`/`info_msg`/`ran_col_str`/`yes_no_prompt`/`progress_bar`/`cmd_arg_help`, plus platform guards `is_linux`/`is_x86`. `error_msg "msg" <exitcode>` prints and exits.
- New scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, derive `script_dir` via `realpath`, source `_util`, support `-h` help.
- Notable: `binstall` (install pinned CLI binaries straight from GitHub releases), `dotinstall`/`dotdok`/`dotmodup` (the install tooling above), `k8stpl`/`k8suser` (kubernetes manifest/user gen), `dksv` (docker image export), `totp-from-key` (TOTP), `sedchad` (sed+grep var replace, used by Dockerfile to swap starship palette).

**Fish functions** live in `dotfiles/.config/fish/functions/*.fish` (autoloaded), e.g. `start_tmux` is invoked at the end of `config.fish`.

**Skills** (`skills/`) — Claude Code skills (`tmux-subagents-claude`, `tmux-agents-codex`) for orchestrating agents in tmux panes. The `tmux-subagents-claude` skill is backed by a standalone Go program (see below), not a script in `scripts/`.

**Go programs** (`go/`) — `module github.com/mbrav/dotfiles/go`, stdlib-only. `go/tmux-subagents-claude/` is the orchestrator CLI behind the `tmux-subagents-claude` skill; install with `go install github.com/mbrav/dotfiles/go/tmux-subagents-claude@latest` (lands in `~/go/bin`, which is on `PATH`). Build/test: `cd go && go test ./... && go vet ./...`. Validate before committing with `gofmt -l`, `go vet`, and `go test`.

## Security

The repo is public. `_secrets` is git-tracked but must only hold placeholder/example values and machine-local config — **never live API keys or tokens**. Before committing changes that touch `_secrets`, verify no real credentials are present. The intended pattern for actual secrets is a gitignored file (`.gitignore` already ignores `scripts/secrets.ini`).
