# Init completions

if status is-interactive
    # init starship
    if command -q starship
        starship init fish --print-full-init | source
    end

    # init zoxide
    if command -q zoxide
        zoxide init fish | source
    end

    # init atuin
    if command -q atuin
        atuin init fish | source
        atuin gen-completions --shell fish | source
    end

    # init talosctl
    if command -q talosctl
        talosctl completion fish | source
    end

    # init headscale
    if command -q headscale
        headscale completion fish | source
    end

    # init netbird
    if command -q netbird
        netbird completion fish | source
    end

    # init cilium
    if command -q cilium
        cilium completion fish | source
    end

    # init hubble
    if command -q hubble
        hubble completion fish | source
    end

    # init herdr
    if command -q herdr
        herdr completion fish | source
    end

end
