## Set values
# Hide welcome message
set fish_greeting
set VIRTUAL_ENV_DISABLE_PROMPT 1

# Set trucolor
set -x COLORTERM truecolor
if type -q bat
    set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
end

# Set settings for https://github.com/franciscolourenco/done
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

## Environment setup
# Apply .profile: use this to put fish compatible .profile stuff in
if test -f ~/.fish_profile
    source ~/.fish_profile
end

# Treat the home venv as a user tools directory, not an active shell venv.
if test "$VIRTUAL_ENV" = "$HOME/.venv"
    set -e VIRTUAL_ENV
    set -e VIRTUAL_ENV_PROMPT
    set -e _OLD_VIRTUAL_PATH
    set -e _OLD_VIRTUAL_PYTHONHOME
    set -e _OLD_FISH_PROMPT_OVERRIDE
end

# Add ~/.local/bin to PATH
if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

## Advanced command-not-found hook
if test -f /usr/share/doc/find-the-command/ftc.fish
    source /usr/share/doc/find-the-command/ftc.fish
end

start_tmux
