#!/usr/bin/env bash

#if [[ -z $DEBUG ]]; then
#	echo "dbg"
#	exit 0
#fi

# Define currency config dynamically
currency_config="USD RUB $,EUR RUB €,CNY RUB ¥"

# Loop through the currency_config
IFS=',' read -r -a currencies <<<"$currency_config"

result=""

# Process each currency pair
for pair in "${currencies[@]}"; do
	# Split the pair into from and to currencies
	cur_from=$(echo "$pair" | awk '{print $1}')
	cur_to=$(echo "$pair" | awk '{print $2}')
	txt_display=$(echo "$pair" | awk '{print $3}')

	#echo "$cur_from $cur_to $txt_display"

	api_url="https://api.exchangerate-api.com/v4/latest/${cur_from}"
	tmp_file="/tmp/${cur_from}.json"

	# Check if the temporary file exists and if it's older than 1 hour
	if [[ ! -f "${tmp_file}" ]] || [[ $(find "${tmp_file}" -mmin +60) ]]; then
		# Call the API and save the result to the temporary file
		curl -s "${api_url}" >"${tmp_file}"
		echo "${api_url} ${tmp_file}"
	fi

	# Output the current date and the exchange rate
	if [[ -f "${tmp_file}" ]]; then
		exchnang_rate=$(cat "$tmp_file" | jq -r ".rates.${cur_to}")
		result="${result}${txt_display}${exchnang_rate} "
	else
		result="error"
	fi
done

echo "${result}" | xargs
