#!/bin/bash
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# BASH OPTIONS
# Enable appending to the history file instead of overwriting it
shopt -s histappend

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# Set the file where the command history is saved
HISTFILE=~/.bash_history

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=999999
HISTFILESIZE=999999

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
# ignoredups: skip duplicates
# ignorespace: skip lines starting with a space
HISTCONTROL=ignoreboth

# Ignore specific trivial commands
HISTIGNORE="ls *:history:cd:cd -:exit"

# Add timestamp to each entry
HISTTIMEFORMAT="%F %T: "

# Ensure history is updated immediately after each command
# `history -a` => append new lines to history file
# `history -c` and `history -r` aren't needed unless you're doing something fancy
# Use a custom PROMPT_COMMAND to avoid overwriting anything pre-existing
#PROMPT_COMMAND="history -a; history -n; $PROMPT_COMMAND"

# Add local bin to path if it exists
[[ -d $HOME/.local/bin ]] && PATH="$PATH:$HOME/.local/bin"
# Load tmux t-smart-tmux-session-manager
# [[ -d $HOME/.config/tmux/plugins/t-smart-tmux-session-manager/bin ]] && PATH="$PATH:$HOME/.config/tmux/plugins/t-smart-tmux-session-manager/bin"

# Load starship prompt if starship is installed:
command -v starship >/dev/null && eval "$(starship init bash)"

# Load zoxide if installed:
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# Load Mcfly history lookup plugin if installed:
command -v mcfly >/dev/null && eval "$(mcfly init bash)"

# Autocompletion

# init talosctl
command -v talosctl >/dev/null && eval "$(talosctl completion bash)"

# init cilium
command -v cilium >/dev/null && eval "$(cilium completion bash)"

# init hubble
command -v hubble >/dev/null && eval "$(hubble completion bash)"

# Advanced command-not-found hook
[[ -f /usr/share/doc/find-the-command/ftc.bash ]] && source /usr/share/doc/find-the-command/ftc.bash

## Run fastfetch, neofetch or screenfetch
if command -v fastfetch &>/dev/null; then
	fastfetch --load-config neofetch.jsonc
elif command -v neofetch &>/dev/null; then
	neofetch
elif command -v screenfetch &>/dev/null; then
	screenfetch
fi

# Pyenv config
[[ -d "$HOME/.pyenv" ]] && export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"
command -v pyenv >/dev/null && eval "$(pyenv virtualenv-init -)"

# Cargo config
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Go config
[[ -d "$HOME/go/bin" ]] && PATH="$PATH:$HOME/go/bin"

# Init custom scripts
[[ -f "$HOME/.config/scripts/_aliases" ]] && source "$HOME/.config/scripts/_aliases"
[[ -f "$HOME/.config/scripts/_secrets" ]] && source "$HOME/.config/scripts/_secrets"

# Load exceutable scripts and add to PATH
[[ -d "$HOME/.config/scripts" ]] && PATH="$PATH:$HOME/.config/scripts"

# Kubectl aliases based on shell
# Based on https://github.com/ahmetb/kubectl-aliases
[[ -f "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases" ]] && source "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases"

# Set trucolor
export COLORTERM=truecolor

# wakatime for bash
#
# include this file in your "~/.bashrc" file with this command:
#   . path/to/bash-wakatime.sh
#
# or this command:
#   source path/to/bash-wakatime.sh
#
# Don't forget to create and configure your "~/.wakatime.cfg" file.

# hook function to send wakatime a tick
pre_prompt_command() {
	version="1.0.0"
	entity=$(echo $(fc -ln -0) | cut -d ' ' -f1)
	[ -z "$entity" ] && return # $entity is empty or only whitespace
	$(git rev-parse --is-inside-work-tree 2>/dev/null) && local project="$(basename $(git rev-parse --show-toplevel))" || local project="Bash"
	(wakatime-cli --write --plugin "bash-wakatime/$version" --entity-type app --project "$project" --entity "$entity" 2>&1 >/dev/null &)
}

command -v wakatime-cli >/dev/null && PROMPT_COMMAND="pre_prompt_command; $PROMPT_COMMAND"

function start_tmux() {
	if ! command -v tmux &>/dev/null; then
		# Check if tmux is installed
		# if not, exit function
		return
	fi

	if [[ "$TERM_PROGRAM" = @(vscode) || -n "$NVIM" || -n "$FLOATERM" ]]; then
		# Check if terminal inside an IDE
		IN_IDE=1
	fi

	if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" || -n "$KONSOLE_DBUS_SESSION" ]]; then
		# $SSH_* - Check if inside a SSH session
		# If so, do not enter a tmux session and exit function

		# $KONSOLE_DBUS_SESSION - Check if inside a Konsole session
		# Since Konsole is assumed to not be the default terminal app
		# Whenever a integrated terminal opens within a KDE framework app
		# exit function
		if [[ -z "$IN_IDE" ]]; then
			# If inside IDE, ignore
			return
		fi
		# echo "🛑 Inside SSH session, not starting tmux session"
	fi

	if [[ -n "$TMUX" || "$TERM" = "screen" ]]; then
		# Check if already inside tmux or custom variable
		# if so, exit function
		return
	fi

	# Attach to tmux session on shell login if tmux is installed
	# Set default session name to "main"
	tmux_session_name="🐺$(whoami)"

	if [[ -n "$IN_IDE" ]]; then
		# Check if term is inside an IDE or other environments
		folder="$(pwd)"
		folder_name="$(basename $folder)"
		tmux_session_name="🖥️$folder_name"
	fi

	# Attach to existing or create a new tmux session
	tmux -2 attach -t "$tmux_session_name" || tmux -2 new-session -s "$tmux_session_name"
}

start_tmux
