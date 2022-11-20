#!/bin/bash

script_dir=$(dirname "$(realpath $0)")
dir="$HOME/.scripts/"
. $script_dir/scripts/colors.sh
. $script_dir/scripts/functions.sh

function install_scripts() {
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
}

function install_dotfiles() {
    cp -vfr $script_dir/dot_files/. ~/
}

echo -e "${GREEN}${BOLD}${script_id} installer"

yes_no_prompt "${GREEN}Install Dot files? ${YELLOW}"
[[ $Y_N -eq 0 ]] && install_dotfiles

yes_no_prompt "${GREEN}Install scripts? ${YELLOW}"
[[ $Y_N -eq 0 ]] && install_scripts

yes_no_prompt "${GREEN}Turn on automatic tmux login for shell? ${YELLOW}"
[[ $Y_N -eq 0 ]] && replace-vars "# start_tmux" "start_tmux" ~/.scripts/functions.sh || info_msg "Tmux will not be started on shell login"

yes_no_prompt "${GREEN}Install Starship? ${YELLOW}"
[[ $Y_N -eq 0 ]] && curl -sS https://starship.rs/install.sh | sh

# info_msg "Finishing up..."
replace-vars "# load_starship" "load_starship" ~/.scripts/functions.sh

success_msg "Install successful! Reload shell."