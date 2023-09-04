#!/bin/bash
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Add local bin to path if it exists
[[ -d $HOME/.local/bin ]] && PATH="$PATH:$HOME/.local/bin"

# Load starship prompt if starship is installed:
command -v starship >/dev/null && eval "$(starship init bash)"

# Load Macfly history lookup plugin if installed:
command -v mcfly >/dev/null && eval "$(mcfly init bash)"

# Advanced command-not-found hook
[[ -f /usr/share/doc/find-the-command/ftc.bash ]] && source /usr/share/doc/find-the-command/ftc.bash

## Run fastfetch, neofetch or screenfetch
if command -v fastfetch &> /dev/null; then
    fastfetch --load-config neofetch
elif command -v neofetch &> /dev/null; then
    neofetch
elif command -v screenfetch &> /dev/null; then
    screenfetch
fi

# Pyenv config
[[ -d "$HOME/.pyenv" ]] && export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"
command -v pyenv >/dev/null && eval "$(pyenv virtualenv-init -)"

# Cargo config
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Init custom scripts
[[ -f "$HOME/.config/scripts/functions.sh" ]] && source "$HOME/.config/scripts/functions.sh"
[[ -f "$HOME/.config/scripts/aliases" ]] && source "$HOME/.config/scripts/aliases"
[[ -f "$HOME/.config/scripts/secrets" ]] && source "$HOME/.config/scripts/secrets"

# Load exceutable scripts and add to PATH
[[ -d "$HOME/.config/scripts/bin" ]] && PATH="$PATH:$HOME/.config/scripts/bin"

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
    $(git rev-parse --is-inside-work-tree 2> /dev/null) && local project="$(basename $(git rev-parse --show-toplevel))" || local project="Bash"
    (wakatime-cli --write --plugin "bash-wakatime/$version" --entity-type app --project "$project" --entity "$entity" 2>&1 > /dev/null &)
}

command -v wakatime-cli > /dev/null && PROMPT_COMMAND="pre_prompt_command; $PROMPT_COMMAND"

