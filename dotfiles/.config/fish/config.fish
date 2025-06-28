## Set values
# Hide welcome message
set fish_greeting
set VIRTUAL_ENV_DISABLE_PROMPT 1
# Set trucolor
set -x COLORTERM truecolor
if type -q bat
    set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
end

# Set kubectl krew
set -l krew_path (set -q KREW_ROOT; and echo $KREW_ROOT/.krew/bin; or echo $HOME/.krew/bin)
if test -d $krew_path
    if not contains -- $krew_path $PATH
        set -gx PATH $PATH $krew_path
    end
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

start_tmux
