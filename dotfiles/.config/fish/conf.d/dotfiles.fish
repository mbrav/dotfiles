# dotfiles.fish - Initialize custom scripts and kubectl aliases

# Source secrets and aliases if scripts exist
if test -f ~/.config/scripts/_secrets
    source ~/.config/scripts/_secrets
end

if test -f ~/.config/scripts/_aliases
    source ~/.config/scripts/_aliases
end

# Add ~/.config/scripts to PATH if it exists and isn't already present
if test -d ~/.config/scripts
    fish_add_path ~/.config/scripts
end

# Source kubectl aliases if available
if test -f ~/.config/scripts/kubectl-aliases/.kubectl_aliases.fish
    source ~/.config/scripts/kubectl-aliases/.kubectl_aliases.fish
end
