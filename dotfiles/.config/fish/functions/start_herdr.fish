# start_herdr.fish
#
# Function: start_herdr
# Description: Starts or attaches to a herdr session for the current project.
#              Herdr is a terminal multiplexer for managing coding agents.
#              Handles edge cases such as running inside an IDE, SSH, or already in herdr.
#
# Usage: start_herdr
#
# Steps:
#   1. Checks if herdr is installed and shell is interactive.
#   2. Detects if running inside an IDE or floating terminal.
#   3. Skips starting herdr if inside SSH unless also in IDE.
#   4. Skips if already inside herdr (HERDR_SESSION set).
#   5. Launches or attaches to herdr session for current project.
function start_herdr -d "Start herdr session for project"
    # Check if herdr is installed and shell is interactive
    if not type -q herdr; or not status --is-interactive
        return
    end

    # Check if inside an IDE or floating terminal
    set -l in_ide
    if contains "$TERM_PROGRAM" vscode; or test -n "$NVIM"; or test -n "$FLOATERM"
        set in_ide 1
    end

    # Check if inside an SSH session
    if test -n "$SSH_CONNECTION"; or test -n "$SSH_CLIENT"; or test -n "$SSH_TTY"
        if not test -n "$in_ide"
            return
        end
    end

    # Check if already inside herdr (herdr sets HERDR_ENV=1 in managed panes)
    if test -n "$HERDR_ENV"; or test -n "$HERDR_PANE_ID"
        return
    end

    # Launch or attach to herdr session
    set -l project_name (basename (pwd))
    echo "🚀 Starting herdr for project: $project_name"
    herdr
end
