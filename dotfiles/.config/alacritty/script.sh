#!/bin/bash

# Define the directory containing the config files
config_dir="$HOME/.config/alacritty/schemes"

# Use ls to find all .toml files and format the output
ls "$config_dir"/*.toml | sed 's|^|  "|; s|$|",|'
