#!/bin/bash

function check_sudo () {
    [[ $(whoami) != root ]] && error_msg "Please run script as root or sudo" 13
    warning_msg "Note: to run sudo and preserve passed env variables run with 'sudo -E'"
}

# Yes no prompt
function yes_no_prompt() {
    # $1 - Space separated string for prompt
    # Returns
    # 1 - yes
    # 0 - no
    while true; do
        read -p "${GREEN}${BOLD}${1} ${YELLOW}${BOLD}y/n${CLEAR}:" Y_N
        case $Y_N in
            y|Y) return 1 ;;
            n|N) return 0 ;;
            *) exit 1 ;;
        esac
    done
}

# Check for passed url
function check_url() {
    # 0 - exists
    # 1 - does not
    if curl --output /dev/null --silent --head --fail "$1"; then
        echo 0
    else
        echo 1
    fi
}

function docker-compose-install() {
    # $1 - Docker compsoe version, otherwise default
    [[ -n $1 ]] && local docker_v=$1 || local docker_v=2.12.2
    local docker_url="https://github.com/docker/compose/releases/download/v${docker_v}/docker-compose-$(uname -s)-$(uname -m)"
    [[ $(check_url "$docker_url") -ne 0 ]] && error_msg "Bad url" 6
    success_msg "Valid url: $docker_url"
    sudo curl -L $docker_url -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    success_msg "gocker compose installed"
    docker-compose --version
}

# Replace text and show interactive
function replace-vars() {
    # $1 - string to find
    # $2 - string to change to
    # $3 - File path
    [[ $# -ne 3 ]] && error_msg "replace_vars() accepts 3 arguments, not $#" 22

    info_msg "Will replace '${1}' with '${2}' in file ${3}"
    grep_command=$(grep "${1}" "${3}")
    info_msg "Before:\n${BLUE}${grep_command}"

    sed -i "s,${1},${2},g" "${3}"

    grep_command=$(grep "${2}" "${3}")
    info_msg "After:\n${BLUE}${grep_command}"
    unset grep_command
}

# Save docker images
function dock-save() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo -e $RED"Must provide 2 arguments, docker image name and tar output file name (no exension)"$CLEAR
        exit 1
    fi
    mkdir -p ~/docker-images
    echo -e $GREEN"Exporting image $YELLOW$1 $GREEN to ~/docker-images/$YELLOW$2.tar.gz"$CLEAR
    docker save $1 | gzip -c > ~/docker-images/$2.tar.gz
}

# Auto completion for docker-save
function _dock-save_completions() {
    [ "${#COMP_WORDS[@]}" != "2" ] && return || \
        COMPREPLY=($(compgen -W "$(docker images --format "{{.Repository}}:{{.Tag}}")" "${COMP_WORDS[1]}"))
}

complete -F _dock-save_completions dock-save

# Interval command
function do-interval() {
    # $1 - command
    # $2 - interval
    [[ $# -ne 2 ]] && error_msg "do-interval accepts 2 arguments, not $#" 22
    watch -n $1 -d=cumulative $2
}

# Max 7z compression
function 7z-max() {
    echo -e $GREEN$BOLD"7z max compression using lzma2"$CLEAR
    echo -e $YELLOW$BOLD"arg1$CLEAR - archive name without extension"
    echo -e $YELLOW$BOLD"arg2$CLEAR - folder name (optional)"
    if [ -z "$1" ]; then
        echo -e $RED$BOLD"Please provide at least one argument"$CLEAR
        exit 1
    elif [ -z "$2" ]; then
        FOLDER_NAME=("$1")
        echo -e $YELLOW"No folder name provided, using "$CYAN$FOLDER_NAME$CLEAR
    else
        FOLDER_NAME=("$2")
    fi
    7z a -m0=lzma2 -mx $1.7z $FOLDER_NAME
}


# Clean non ascii chars from a file
function ascii-clean() {
    local temp_file="$(rand-hex-ssl 6).tmp"
    tr -cd '\11\12\15\40-\176' < $1 > $temp_file
    mv $temp_file $1
}

function git-cred() {
    if [[ $PWD == *"$USER/dev/work"* ]]; then
        git-cred-mbrav
    else
        git-cred-mbrav
    fi
    echo "User:  $(git config user.name)"
    echo "Email: $(git config user.email)"
    echo "Key:   $(git config user.signingkey)"
}

