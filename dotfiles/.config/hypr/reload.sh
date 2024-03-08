#!/usr/bin/env bash
# Reload various componenets

# Get Waybar PID
wb_id=$(pgrep waybar)

notify-send "Restarting Waybar PID ${wb_id}" -u low -c dotfiles -t 4000

# Reload PID if defined
if [ -n $wb_id ]; then
	kill $wb_id
	waybar &
fi

if [ $? -eq 0 ]; then
	notify-send "Waybar restarted" -u normal -c dotfiles -t 4000
else
	notify-send "Waybar restart FAILED!" -u critical -c dotfiles -t 4000
fi

hyprctl reload

if [ $? -eq 0 ]; then
	notify-send "Hyperland reloaded" -u normal -c dotfiles -t 4000
else
	notify-send "Hyperland reload FAILED!" -u critical -c dotfiles -t 4000
fi
