# Run fastfetch/neofetch/screenfetch on interactive session start
if status --is-interactive
    if type -q fastfetch
        fastfetch --config neofetch.jsonc
    else if type -q neofetch
        neofetch
    else if type -q screenfetch
        screenfetch
    end
end
