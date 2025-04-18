# Init completions

if status --is-interactive
    # init starship
    if type -q starship
        starship init fish --print-full-init | source
    end

    # init zoxide
    if type -q zoxide
        zoxide init fish | source
    end

    # init mcfly
    if type -q mcfly
        mcfly init fish | source
    end

    # init talosctl
    if type -q talosctl
        talosctl completion fish | source
    end

    # init headscale
    if type -q headscale
        headscale completion fish | source
    end

    # init cilium
    if type -q cilium
        cilium completion fish | source
    end

    # init hubble
    if type -q hubble
        hubble completion fish | source
    end
end
