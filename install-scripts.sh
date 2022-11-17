#!/bin/bash

script_dir=$(dirname "$(realpath $0)")
dir="$HOME/.scripts/"
. $script_dir/scripts/colors.sh
. $script_dir/scripts/functions.sh

info_msg "Scripts installer"

read -p "${GREEN}Enter path (default ${dir}): ${YELLOW}" new_dir
[[ -n $new_dir ]] && dir=$(realpath -m $new_dir)

[[ -d $dir ]] && info_msg "Will overwrite files in ${dir} ${YELLOW}" || mkdir -pv $dir
cp -vf $script_dir/scripts/* $dir

if [[ ! -f ~/.bashrc ]] || ! grep -q "${script_id}" ~/.bashrc; then
    info_msg "Appending file sourcing to bash"
    echo "# ${script_id} BEGIN" >> ~/.bashrc
    for file in $dir*; do 
        echo ". $file" >> ~/.bashrc
        success_msg "Sourced $file"
    done
    echo "# ${script_id} END" >> ~/.bashrc
else
    warning_msg "Files sourced already in .bashrc"
fi

success_msg "Install successful! Reload shell."