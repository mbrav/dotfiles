# Init custom scripts
source ~/.config/scripts/_secrets
source ~/.config/scripts/_aliases

# Load exceutable scripts and add to PATH
if test -d ~/.config/scripts
    if not contains -- ~/.config/scripts $PATH
        set -p PATH ~/.config/scripts
    end
end

# Kubectl aliases based on shell 
# Based on https://github.com/ahmetb/kubectl-aliases
if test -d ~/.config/scripts/kubectl-aliases
    source ~/.config/scripts/kubectl-aliases/.kubectl_aliases.fish
end
