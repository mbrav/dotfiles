# dotfiles.fish - Initialize custom scripts and kubectl aliases

if test -f ~/.profile
    source ~/.profile
end

if test -f ~/.config/scripts/_aliases
    source ~/.config/scripts/_aliases
end

# Source kubectl aliases if available
if test -f ~/.config/scripts/kubectl-aliases/.kubectl_aliases.fish
    source ~/.config/scripts/kubectl-aliases/.kubectl_aliases.fish
end
