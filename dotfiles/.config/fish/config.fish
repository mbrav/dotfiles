## Set values
# Hide welcome message
set fish_greeting
set VIRTUAL_ENV_DISABLE_PROMPT 1
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

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

# Add depot_tools to PATH
if test -d ~/Applications/depot_tools
    if not contains -- ~/Applications/depot_tools $PATH
        set -p PATH ~/Applications/depot_tools
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

# Copy DIR1 DIR2
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | trim-right /)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

## Run fastfetch, neofetch or screenfetch if session is interactive
if status --is-interactive
    if type -q fastfetch
        fastfetch --load-config neofetch
    else if type -q neofetch
        neofetch
    else if type -q screenfetch
        screenfetch
    end
end

## MY MODS

# Set trucolor
set -x COLORTERM truecolor

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

# init mcfly
if type -q mcfly
    mcfly init fish | source
end 

# init starship
function load_starship
    if status --is-interactive && type -q starship
        source (starship init fish --print-full-init | psub)
    end
end

function start_tmux
    if not type -sq tmux; and not status --is-interactive
        # Check if tmux is installed
        # if not, exit function
        # echo "🛑 Tmux not installed, not starting tmux session"
        return
    end

    if contains "$TERM_PROGRAM" vscode; or test -n "$NVIM"
        # Check if terminal inside an IDE
        set IN_IDE 1
    end
    
    if test -n "$SSH_CONNECTION"; or test -n "$SSH_CLIENT"; or test -n "$SSH_TTY"; or test -n "$KONSOLE_DBUS_SESSION"

        # $SSH_* - Check if inside a SSH session
        # If so, do not enter a tmux session and exit function

        # $KONSOLE_DBUS_SESSION - Check if inside a Konsole session
        # Since Konsole is assumed to not be the default terminal app
        # Whenever a integrated terminal opens within a KDE framework app
        # exit function

        if test -z "$IN_IDE"
            # If inside IDE, ignore
            return
        end
        # echo "🛑 Inside SSH session, not starting tmux session"
    end

    if test -n "$TMUX"; or test "$SHELL" = "screen"
        # Check if already inside tmux or custom variable
        # if so, exit function
        return
    end

    # Attach to tmux session on shell login if tmux is installed
    # Set default session name to a random animal icon "main"
    # set animal_icons ("🐺" "🐯" "🦁" "🐪" "🐧" "🦩" "🦆" "🦅" "🐼" "🦏" "🦀" "🦂" "🕷️" "🦍" "🦊" "🦖" "🐊" "🐉" "🐲" "🐍" "🐋" "🐬" "🐙")
    set tmux_session_name "🐺$(whoami)"

    if test -n "$IN_IDE"
        # Check if term is inside an IDE or other environments
        set folder "$(pwd)"
        set folder_name "$(basename $folder)"
        set tmux_session_name "🖥️$folder_name"
    end

    # Attach to existing or create a new tmux session
    tmux -2 attach -t "$tmux_session_name"; or tmux -2 new-session -s "$tmux_session_name"
end

load_starship
start_tmux

