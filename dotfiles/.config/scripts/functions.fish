#!/usr/local/bin/fish

function load_starship
    if type -q starship
        starship init fish | source
    end
end

# If interactive, don't do anything
if not test -t 0
    return
end

function start_tmux
    if not type -sq tmux
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
    set tmux_session_name "🐺main"

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

# Set trucolor
set -x COLORTERM truecolor

