#!/usr/bin/env bash
#
# Gets your wakatime usage for today

time_today=$(wakatime-cli --today)
if [ -n "$time_today" ]; then
	printf "%s" "$time_today"
	notify-send "Wakatime coding today" "$time_today"
else
	printf "Error"
	notify-send "Wakatime API Error"
fi
