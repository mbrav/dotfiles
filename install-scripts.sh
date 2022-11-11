#!/bin/bash

script_dir=$(dirname "$(realpath $0)")
dir="$HOME/.scripts/"
. $script_dir/scripts/colors.sh
. $script_dir/scripts/functions.sh

info_msg "Scripts installer"

read -p "${GREEN}Enter path (default ${dir}): ${YELLOW}" new_dir
[[ -n $new_dir ]] && dir=$(realpath -m $new_dir)

[[ -d $dir ]] && info_msg "Will overwrite files in $dir" || mkdir -pv $dir
cp -vf $script_dir/scripts/* $dir

info_msg "Appending files to bash"
echo "# Script install" >> ~/.bashrc
for file in $dir*; do 
    echo ". $file" >> ~/.bashrc
    success_msg "Sourced $file"
done

success_msg "Install successful! Reload shell."