#!/bin/bash

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Load starship prompt if starship is installed
if  [ -x /usr/bin/starship ]; then
    __main() {
        local major="${BASH_VERSINFO[0]}"
        local minor="${BASH_VERSINFO[1]}"

        if ((major > 4)) || { ((major == 4)) && ((minor >= 1)); }; then
            source <("/usr/bin/starship" init bash --print-full-init)
        else
            source /dev/stdin <<<"$("/usr/bin/starship" init bash --print-full-init)"
        fi
    }
    __main
    unset -f __main
fi

# Advanced command-not-found hook
[[ -f /usr/share/doc/find-the-command/ftc.bash ]] && source /usr/share/doc/find-the-command/ftc.bash

# # Rerun config
# export PATH=$PATH:$HOME/bin/.rerun
# export RERUN_MODULES=$HOME/bin/.rerun/modules
# [ -r $HOME/bin/.rerun/etc/bash_completion.sh ] && source $HOME/bin/.rerun/etc/bash_completion.sh
# [ -t 0 ] && export RERUN_COLOR=true

# Pyenv config
[[ -d "$HOME/.pyenv" ]] && export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# NPM config
export PATH="$HOME/.npm-global/bin:$PATH"

# Cargo config
# [[ -d "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
source "$HOME/.cargo/env"


