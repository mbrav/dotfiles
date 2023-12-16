#!/usr/bin/env bash
mbrav_dotfiles_v="0.3.3"
script_id="mbrav/dotfiles v${mbrav_dotfiles_v}"
script_dir="$(dirname "$(realpath "$0")")"
source "${script_dir}/dotfiles/.config/scripts/_util"

function install_scripts() {
	read -p "${GREEN}Enter path (default ${dir}): ${YELLOW}" new_dir
	[[ -n $new_dir ]] && dir=$(realpath -m $new_dir)

	[[ -d $dir ]] && info_msg "Will overwrite files in ${dir} ${YELLOW}" || mkdir -pv $dir
	cp -vf $script_dir/scripts/* $dir

	if [[ ! -f ~/.bashrc ]] || ! grep -q "${script_id}" ~/.bashrc; then
		info_msg "Appending file sourcing to bash"
		echo "# ${script_id} BEGIN" >>~/.bashrc
		for file in $dir*; do
			echo ". $file" >>~/.bashrc
			success_msg "Sourced $file"
		done
		echo "# ${script_id} END" >>~/.bashrc
	else
		warning_msg "Files sourced already in .bashrc"
	fi
}

function dotfiles_symlink() {
	# List conf files in .config
	local dir_ls=($(ls "$script_dir/dotfiles/.config"))

	# Loop through contents
	for item in "${dir_ls[@]}"; do
		# Check item full path
		local item_path="$script_dir/dotfiles/.config/$item"
		if [ -f $item_path ] || [ -d $item_path ] && [ -z "$force" ]; then
			info_msg "Item $item_path exists"
			yes_no_prompt "${GREEN}Replace $item_path with new symlink?${YELLOW}" &&
				rm -rfv "$HOME/.config/$item" &&
				ln -sv "$item_path" "$HOME/.config/$item"
		else
			info_msg "Symlinking file $item_path to $HOME/.config/$item"
			rm -rfv "$HOME/.config/$item"
			ln -sv "$item_path" "$HOME/.config/$item"
		fi
	done

	# List conf files in home
	local dir_ls=(".bashrc" ".gitconfig" ".stignore" ".vimrc" ".vimrc.plug")

	for item in "${dir_ls[@]}"; do
		local item_path="$script_dir/dotfiles/$item"
		if [ -f $item_path ] || [ -d $item_path ] && [ -z "$force" ]; then
			info_msg "Item $item_path exists"
			yes_no_prompt "${GREEN}Replace $item_path with new symlink?${YELLOW}" &&
				rm -fv "$HOME/$item" &&
				ln -sv "$item_path" "$HOME/$item"
		else
			info_msg "Symlinking file $item_path to $HOME/$item"
			rm -fv "$HOME/$item"
			ln -sv "$item_path" "$HOME/$item"
		fi
	done
}

ran_col_str "${script_id} installer"
if [[ -z "$force" ]]; then
	warning_msg "Script in interative mode. Use force=1 ./install.sh for non-interactive install"
	yes_no_prompt "${GREEN}Install Dotfiles as symlinks? ${YELLOW}" &&
		dotfiles_symlink
else
	info_msg "Installing dotfiles non-interactively"
	dotfiles_symlink
fi

[[ $? -ne 0 ]] && error_msg "Failed to install dotfiles" 1 ||
	success_msg "Dotfiles install successfuly! Reload shell."

exit 0
