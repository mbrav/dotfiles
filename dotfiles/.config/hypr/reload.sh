#!/usr/bin/env bash
# Reload various componenets

# Get Waybar PID
wb_id=$(pgrep waybar)

notify-send "Restarting Waybar (id ${wb_id})" -u low -c dotfiles -t 1000

# Reload PID if defined
if [ -n $wb_id ]; then
	kill -SIGUSR2 $wb_id
fi

if [ $? -eq 0 ]; then
	notify-send "Waybar restarted" -u low -c dotfiles -t 1000
else
	notify-send "Waybar restart FAILED!" -u critical -c dotfiles -t 1000
fi
