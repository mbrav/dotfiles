#!/usr/bin/env bash

# Define the temporary file to store the Bitcoin price
txt_display="₿"
cur_to="usd"
tmp_file="/tmp/BTC.json"
api_url="https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=${cur_to}"

# Function to fetch the Bitcoin price
fetch_bitcoin_price() {
	# Call the API and save the result to the temporary file
	curl -s "${api_url}" -o "${tmp_file}"
}

# Check if the temporary file exists and if it's older than 1 hour
if [[ ! -f "${tmp_file}" ]] || [[ $(find "${tmp_file}" -mmin +10) ]]; then
	fetch_bitcoin_price
fi

# Output the current date and the Bitcoin price
if [[ -f "${tmp_file}" ]]; then
	btc_price_to_usd=$(jq -r ".bitcoin.${cur_to}" "$tmp_file")
	echo "${txt_display}${btc_price_to_usd}"
else
	echo "No BTC"
fi
