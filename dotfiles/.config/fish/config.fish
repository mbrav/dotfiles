## Set values
# Hide welcome message
set fish_greeting
set VIRTUAL_ENV_DISABLE_PROMPT 1
# Set trucolor
set -x COLORTERM truecolor
if type -q bat
    set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
end

## Export variable need for qt-theme
if type qtile >>/dev/null 2>&1
    set -x QT_QPA_PLATFORMTHEME qt5ct
end

# Set settings for https://github.com/franciscolourenco/done
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

## Environment setup
# Apply .profile: use this to put fish compatible .profile stuff in
if test -f ~/.fish_profile
    source ~/.fish_profile
end

# Add ~/.local/bin to PATH
if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

# Add /opt/homebrew/bin/to PATH
if test -d /opt/homebrew/bin
    if not contains -- /opt/homebrew/bin $PATH
        set -p PATH /opt/homebrew/bin
    end
end

## Advanced command-not-found hook
if test -f /usr/share/doc/find-the-command/ftc.fish
    source /usr/share/doc/find-the-command/ftc.fish
end

## Functions
# Functions needed for !! and !$ https://github.com/oh-my-fish/plugin-bang-bang
function __history_previous_command
    switch (commandline -t)
        case "!"
            commandline -t $history[1]
            commandline -f repaint
        case "*"
            commandline -i !
    end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

if [ "$fish_key_bindings" = fish_vi_key_bindings ]
    bind -Minsert ! __history_previous_command
    bind -Minsert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

# Fish command history
function history
    # builtin history --show-time='%F %T '
    builtin history
end

function backup --argument filename
    cp $filename $filename.bak
end

## Run fastfetch, neofetch or screenfetch if session is interactive
if status --is-interactive
    if type -q fastfetch
        fastfetch --load-config neofetch.jsonc
    else if type -q neofetch
        neofetch
    else if type -q screenfetch
        screenfetch
    end
end

# Init custom scripts
source ~/.config/scripts/_secrets
source ~/.config/scripts/_aliases

# Load exceutable scripts and add to PATH
if test -d ~/.config/scripts
    if not contains -- ~/.config/scripts $PATH
        set -p PATH ~/.config/scripts
    end
end

# Kubectl aliases based on shell 
# Based on https://github.com/ahmetb/kubectl-aliases
if test -d ~/.config/scripts/kubectl-aliases
    source "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases.fish"
end

# Cargo config
if test -d "$HOME/.cargo/bin"
    fish_add_path $HOME/.cargo/bin
end

# Init pyenv if available
if test -d ~/.pyenv
    set -Ux PYENV_ROOT $HOME/.pyenv
    fish_add_path $PYENV_ROOT/bin
    status --is-interactive; and pyenv init - | source
    status --is-interactive; and pyenv virtualenv-init - | source
    source (pyenv root)/completions/pyenv.fish
end

# Init completions

# init starship
if status --is-interactive && type -q starship
    source (starship init fish --print-full-init | psub)
end

# init zoxide
if status --is-interactive && type -q zoxide
    zoxide init fish | source
end

# init mcfly
if status --is-interactive && type -q mcfly
    mcfly init fish | source
end

# init talosctl
if status --is-interactive && type -q talosctl
    talosctl completion fish | source
end

# init headscale
if status --is-interactive && type -q headscale
    headscale completion fish | source
end

# init cilium
if status --is-interactive && type -q cilium
    cilium completion fish | source
end

# init hubble
if status --is-interactive && type -q hubble
    hubble completion fish | source
end

start_tmux
