#!/usr/bin/env bash
#
# Pings server

ping_server=google.com
ping_time=$(ping -c 1 $ping_server | tail -1 | awk '{print $4}' | cut -d '.' -f 1)
printf "%s" $ping_time
