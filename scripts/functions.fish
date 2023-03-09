#!/usr/local/bin/fish

set mbrav_scripts_v "0.1.4"
set script_id "mbrav/configs v$mbrav_scripts_v"

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

    if test -n "$TMUX"
        # Check if already inside tmux
        # if so, exit function
        return
    end

    # Set default session name to "main"
    set tmux_session_name "🐺main"

    if test -n "$TERM_PROGRAM"; and contains "$TERM_PROGRAM" vscode my_ide_name
        # Check if term is inside an IDE or other environments
        set project_folder "(pwd)"
        set project_folder_name "(basename $project_folder)"
        set tmux_session_name "🖥️$project_folder_name"
    end

    if test -n "$SSH_CONNECTION"; and test -n "$SSH_CLIENT"; and test -n "$SSH_TTY"; and test -n "$project_folder"
        # Check if inside a SSH session
        # And if not inside a term program in cases where VScode Server is used
        # If so, do not enter a tmux session and exit function
        echo "🛑 Inside SSH session, not starting tmux session"
        return
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
