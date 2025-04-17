#!/usr/bin/env bash

# Define the temporary file to store the exchange rate
cur_from="USD"
cur_to="RUB"
txt_display="₽"
tmp_file="/tmp/${cur_from}.json"
api_url="https://api.exchangerate-api.com/v4/latest/${cur_from}"

# Function to fetch the exchange rate
fetch_exchange_rate() {
	# Call the API and save the result to the temporary file
	# curl -s "$API_URL" | jq -r '.rates.RUB' >"$TMP_FILE"
	curl -s "${api_url}" >"${tmp_file}"
}

# Check if the temporary file exists and if it's older than 1 hour
if [[ ! -f "${tmp_file}" ]] || [[ $(find "${tmp_file}" -mmin +60) ]]; then
	fetch_exchange_rate
fi

# Output the current date and the exchange rate
if [[ -f "${tmp_file}" ]]; then
	EXCHANGE_RATE=$(cat "$tmp_file" | jq -r ".rates.${cur_to}")
	echo "${txt_display}${EXCHANGE_RATE}"
else
	echo "No exchange"
fi
