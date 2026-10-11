## Set values
# Hide welcome message
set -g fish_greeting
set -gx VIRTUAL_ENV_DISABLE_PROMPT 1

# Set truecolor
set -gx COLORTERM truecolor
if command -q bat
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
    # groff emits SGR escapes by default; `col -b` strips only the ESC byte and
    # leaves "[1m"/"[4m" as literal text. -c disables SGR so groff uses legacy
    # backspace-overstrike, which col -b collapses and bat re-highlights.
    set -gx MANROFFOPT -c
end

# done (https://github.com/franciscolourenco/done) reads universals, which persist
# on their own. Setting them here every startup would make edits to this file
# silently ineffective, so configure with `set -U` once from the prompt instead.

## Environment setup
# Apply .profile: use this to put fish compatible .profile stuff in.
# Sourced after conf.d, so it can intentionally override PATH from path.fish.
if test -f ~/.fish_profile
    source ~/.fish_profile
end

## Advanced command-not-found hook
if test -f /usr/share/doc/find-the-command/ftc.fish
    source /usr/share/doc/find-the-command/ftc.fish
end

# start_tmux
start_herdr
