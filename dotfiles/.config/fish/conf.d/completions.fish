
# Init completions

# init starship
if status --is-interactive && type -q starship
    source (starship init fish --print-full-init | psub)
end

# init zoxide
if status --is-interactive && type -q zoxide
    zoxide init fish | source
end

# init mcfly
if status --is-interactive && type -q mcfly
    mcfly init fish | source
end

# init talosctl
if status --is-interactive && type -q talosctl
    talosctl completion fish | source
end

# init headscale
if status --is-interactive && type -q headscale
    headscale completion fish | source
end

# init cilium
if status --is-interactive && type -q cilium
    cilium completion fish | source
end

# init hubble
if status --is-interactive && type -q hubble
    hubble completion fish | source
end
