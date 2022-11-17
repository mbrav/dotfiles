#!/bin/bash

script_dir=$(dirname "$(realpath $0)")
dir="$HOME/.scripts/"
. $script_dir/scripts/colors.sh
. $script_dir/scripts/functions.sh

info_msg "Dot files installer"

cp -vfr $script_dir/dot_files/. ~/

success_msg "Install successful! Reload shell."