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
        # Check if tmux is insalled
        # if not, exit function
        echo "🛑 Tmux not installed, not starting tmux session"
        return
    end

    if test -n "$SSH_CONNECTION"; and test -n "$SSH_CLIENT"; and test -n "$SSH_TTY"
        # Check if inside a SSH session
        # If so, do not enter a tmux session and exit function
        echo "🛑 Inside SSH session, not starting tmux session"
        return
    end

    if test -n "$TMUX"; and test "$SHELL" = "screen"
        # Check if already inside tmux or custom variable
        # if so, exit function
        return
    end

    # Attach to tmux session on shell login if tmux is installed
    # Set default session name to a random animal icon "main"
    # set animal_icons ("🐺" "🐯" "🦁" "🐪" "🐧" "🦩" "🦆" "🦅" "🐼" "🦏" "🦀" "🦂" "🕷️" "🦍" "🦊" "🦖" "🐊" "🐉" "🐲" "🐍" "🐋" "🐬" "🐙")
    set tmux_session_name "🐺main"

    if test -n "$TERM_PROGRAM"; and contains "$TERM_PROGRAM" vscode my_ide_name
        # Check if term is inside an IDE or other environments
        set folder "$(pwd)"
        set folder_name "$(basename $folder)"
        set tmux_session_name "🖥️$folder_name"
    end

    # Attach to existing or create a new tmux session
    if test -n "(tmux ls | grep "$tmux_session_name")"
        echo "🚪 Tmux session '$tmux_session_name' exists, entering"
    else
        echo "🪄 Tmux session '$tmux_session_name' does not exist, creating"
    end
    tmux -2 attach -t "$tmux_session_name"; or tmux -2 new-session -s "$tmux_session_name"
end

load_starship
start_tmux
