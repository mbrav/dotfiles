# Create a new tmux window by picking a folder from ~/dev with fzf.
# The window name is set to the selected folder's basename.
# Intended to be launched via a tmux display-popup binding.

script_dir="$(dirname "$(realpath "$0")")"
source "${script_dir}/../scripts/_util"

# Build preview command: prefer eza, fall back to ls
if command -v eza >/dev/null; then
  preview_cmd="eza -al --git --color=always --color-scale --group-directories-first --icons {1}"
else
  preview_cmd="ls -lahg --color=auto {1}"
fi

selected_dir="$(find ~/dev/* -type d | fzf \
  --header "Select folder to open in new tmux window" \
  --preview-window "up:50%" \
  --preview-label "Folder contents" \
  --preview "$preview_cmd")"

if [[ -z "$selected_dir" ]]; then
  warning_msg "No folder selected, aborting."
  exit 0
fi

win_name="$(basename "$selected_dir")"

# Deduplicate: append -N suffix if name already exists in current session
base_name="$win_name"
suffix=2
while tmux list-windows -F '#{window_name}' | grep -qx "$win_name"; do
  win_name="${base_name}-${suffix}"
  suffix=$((suffix + 1))
done
[[ "$win_name" != "$base_name" ]] && info_msg "Renamed to avoid duplicate: ${BOLD}${win_name}${CLEAR}" ""

tmux new-window -n "$win_name" -c "$selected_dir" -e "TMUX_WIN=$win_name"
success_msg "Opened: ${win_name}"
