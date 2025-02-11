# Init pyenv if available
if test -d ~/.pyenv
    set -Ux PYENV_ROOT $HOME/.pyenv
    fish_add_path $PYENV_ROOT/bin
    status --is-interactive; and pyenv init - | source
    status --is-interactive; and pyenv virtualenv-init - | source
    source (pyenv root)/completions/pyenv.fish
end
