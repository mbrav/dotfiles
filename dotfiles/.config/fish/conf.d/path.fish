# PATH — single source of truth. First entry wins.
#
# Why one file: fish_add_path calls spread across conf.d make priority an emergent
# property of alphabetical filenames. Here the order is just the list below.

# Migrate off universal fish_user_paths. Once that universal exists, a bare
# fish_add_path keeps writing to it forever, so PATH ends up in gitignored
# machine-local state and a fresh clone no longer reproduces it.
set -q fish_user_paths; and set -eU fish_user_paths
set -q PYENV_ROOT; and set -eU PYENV_ROOT
set -gx PYENV_ROOT $HOME/.pyenv

# Drop duplicates inherited from nested shells and macOS path_helper.
# fish_add_path --move only relocates one copy, so this pass has to come first.
set -l seen
for p in $PATH
    contains -- $p $seen; or set -a seen $p
end
set -gx PATH $seen

# --path writes to global $PATH, never to universals.
# --move re-prioritises entries the login env already placed (path_helper pushes
# them to the tail, where a plain fish_add_path would see them and no-op).
# Missing directories are skipped, so this list is portable to the Alpine image.
fish_add_path --path --move \
    ~/.venv/bin \
    ~/.local/bin \
    ~/.cargo/bin \
    ~/.config/scripts \
    (set -q KREW_ROOT; and echo $KREW_ROOT/.krew/bin; or echo ~/.krew/bin) \
    ~/go/bin \
    ~/.local/share/npm/bin \
    ~/.pulumi/bin \
    ~/.pyenv/bin \
    /opt/homebrew/bin \
    /usr/local/go/bin
