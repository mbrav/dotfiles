# Run fastfetch/neofetch/screenfetch on interactive session start
if status is-interactive
    if command -q fastfetch
        fastfetch --config neofetch.jsonc
    else if command -q neofetch
        neofetch
    else if command -q screenfetch
        screenfetch
    end
end
