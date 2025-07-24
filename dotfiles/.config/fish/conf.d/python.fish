# Initializes pyenv and its virtualenv if available.
# Only runs in interactive shells for performance.
# Adds pyenv binaries to PATH and enables completions.

if test -d ~/.pyenv
    set -Ux PYENV_ROOT $HOME/.pyenv
    fish_add_path $PYENV_ROOT/bin

    if status --is-interactive
        pyenv init - | source
        pyenv virtualenv-init - | source
        source (pyenv root)/completions/pyenv.fish
    end
end
