#!/bin/bash

# wakatime for bash
#
# include this file in your "~/.bashrc" file with this command:
#   . path/to/bash-wakatime.sh
#
# or this command:
#   source path/to/bash-wakatime.sh
#
# Don't forget to create and configure your "~/.wakatime.cfg" file.

# hook function to send wakatime a tick
pre_prompt_command() {
    version="1.0.0"
    entity=$(echo $(fc -ln -0) | cut -d ' ' -f1)
    [ -z "$entity" ] && return # $entity is empty or only whitespace
    $(git rev-parse --is-inside-work-tree 2> /dev/null) && local project="$(basename $(git rev-parse --show-toplevel))" || local project="Bash"
    (wakatime-cli --write --plugin "bash-wakatime/$version" --entity-type app --project "$project" --entity "$entity" 2>&1 > /dev/null &)
}

command -v wakatime-cli > /dev/null && PROMPT_COMMAND="pre_prompt_command; $PROMPT_COMMAND"

function start_tmux() {
    if ! command -v tmux &> /dev/null; then
        # Check if tmux is installed
        # if not, exit function
        return
    fi
 
    if [[ -n "$NVIM" || "$TERM_PROGRAM" = @(vscode) ]]; then
        # Check if terminal inside an IDE
        IN_IDE=1
    fi

    if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" || -n "$KONSOLE_DBUS_SESSION"  ]]; then
        # $SSH_* - Check if inside a SSH session
        # If so, do not enter a tmux session and exit function

        # $KONSOLE_DBUS_SESSION - Check if inside a Konsole session
        # Since Konsole is assumed to not be the default terminal app
        # Whenever a integrated terminal opens within a KDE framework app
        # exit function
        if [[ -z "$IN_IDE" ]]; then
            # If inside IDE, ignore
            return
        fi
        # echo "🛑 Inside SSH session, not starting tmux session"
    fi

    if [[ -n "$TMUX" || "$TERM" = "screen" ]]; then
        # Check if already inside tmux or custom variable
        # if so, exit function
        return
    fi

    # Attach to tmux session on shell login if tmux is installed
    # Set default session name to "main"
    tmux_session_name="🐺main"

    if [[ -n "$IN_IDE" ]]; then
        # Check if term is inside an IDE or other environments
        folder="$(pwd)"
        folder_name="$(basename $folder)"
        tmux_session_name="🖥️$folder_name"
    fi

    # Attach to existing or create a new tmux session
    tmux -2 attach -t "$tmux_session_name" || tmux -2 new-session -s "$tmux_session_name"
}

start_tmux
