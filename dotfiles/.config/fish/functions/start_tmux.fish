# start_tmux.fish
#
# Function: start_tmux
# Description: Starts a tmux session with a custom icon as the session name.
#              Handles various edge cases such as running inside an IDE, SSH, or Konsole.
#              Attaches to an existing "main" session if available, otherwise creates a new one.
#
# Usage: start_tmux
#
# Steps:
#   1. Checks if tmux is installed and shell is interactive.
#   2. Detects if running inside an IDE or floating terminal.
#   3. Skips starting tmux if inside SSH/Konsole unless also in IDE.
#   4. Skips if already inside tmux.
#   5. Sets a random animal icon for the session name, or uses folder name if in IDE.
#   6. Attaches to existing "main" session or creates a new one.
function start_tmux -d "Start tmux session with custom icon"
    # Check if tmux is installed and shell is interactive
    if not type -q tmux; or not status --is-interactive
        #echo "🛑 Tmux not installed or shell not interactive, not starting tmux session"
        return
    end

    # Check if inside an IDE or floating terminal
    set -l in_ide
    if contains "$TERM_PROGRAM" vscode; or test -n "$NVIM"; or test -n "$FLOATERM"
        set in_ide 1
    end

    # Check if inside an SSH session or Konsole
    if test -n "$SSH_CONNECTION"; or test -n "$SSH_CLIENT"; or test -n "$SSH_TTY"; or test -n "$KONSOLE_DBUS_SESSION"
        if not test -n "$in_ide"
            #echo "🛑 Inside SSH session, not starting tmux session"
            return
        end
    end

    # Check if already inside tmux
    if test -n "$TMUX"
        return
    end

    # Set default session name with a random animal icon and "main"
    set -l animal_icons "🐺" "🐯" "🦁" "🐪" "🐧" "🦩" "🦆" "🦅" "🐼" "🦏" "🦀" "🦂" "🕷️" "🦍" "🦊" "🦖" "🐊" "🐉" "🐲" "🐍" "🐋" "🐬" "🐙"
    set -l random_icon (echo $animal_icons | tr ' ' '\n' | shuf -n 1)
    set -l default_session_name "$random_icon main"

    # Override session name if inside IDE
    if test -n "$in_ide"
        set -l folder_name (basename (pwd))
        set default_session_name "🖥️$folder_name"
    end

    # Check if any existing session contains "main"
    set -l main_session (tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -m 1 "main")
    if test -n "$main_session"
        echo "🔄 Attaching to existing tmux session: $main_session"
        tmux -2 attach -t "$main_session"
    else
        echo "✨ Starting new tmux session: $default_session_name"
        tmux -2 new-session -s "$default_session_name"
    end
end
