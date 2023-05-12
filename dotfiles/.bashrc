#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Load starship prompt if starship is installed:
command -v starship >/dev/null && eval "$(starship init bash)"

# Load Macfly history lookup plugin if installed:
command -v mcfly >/dev/null && eval "$(mcfly init bash)"

# Advanced command-not-found hook
[[ -f /usr/share/doc/find-the-command/ftc.bash ]] && source /usr/share/doc/find-the-command/ftc.bash

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

# Kubectl aliases based on shell 
# Based on https://github.com/ahmetb/kubectl-aliases
[[ -d "$HOME/.config/scripts/kubectl-aliases" ]] && source "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases"
