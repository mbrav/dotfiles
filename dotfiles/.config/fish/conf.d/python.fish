# pyenv. PATH entries live in path.fish; PYENV_ROOT is set there too.
# Only the shim/completion init happens here, and only when interactive.

if test -d ~/.pyenv; and status is-interactive
    pyenv init - | source
    pyenv virtualenv-init - | source
    source (pyenv root)/completions/pyenv.fish
end
