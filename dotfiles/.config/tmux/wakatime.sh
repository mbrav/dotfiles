#!/usr/bin/env bash

# Define the temporary file to store the exchange rate
txt_display="⏳"
tmp_file="/tmp/wakatime_today.txt"

if [[ ! -f ~/.wakatime/wakatime-cli ]]; then
	echo "No waka"
	exit 1
fi

# Function to fetch the exchange rate
fetch_wakatime() {
	~/.wakatime/wakatime-cli --today --today-hide-categories true >"${tmp_file}"
}

# Check if the temporary file exists and if it's older than 5 minutes
if [[ ! -f "${tmp_file}" ]] || [[ $(find "${tmp_file}" -mmin +5) ]]; then
	fetch_wakatime
fi

# Output the current date and the exchange rate
if [[ -f "${tmp_file}" ]]; then
	wakatime_today=$(cat "$tmp_file")
	echo "${txt_display}${wakatime_today}"
else
	echo "Waka error"
fi
