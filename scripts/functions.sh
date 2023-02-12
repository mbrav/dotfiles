#!/bin/bash

mbrav_scripts_v="0.1.4"
script_id="mbrav/configs v${mbrav_scripts_v}"

# Load starship prompt if starship is installed
function load_starship () {
    if [ -x "$(command -v starship)" ]; then
        __main() {
            local major="${BASH_VERSINFO[0]}"
            local minor="${BASH_VERSINFO[1]}"

            if ((major > 4)) || { ((major == 4)) && ((minor >= 1)); }; then
                source <(starship init bash --print-full-init)
            else
                source /dev/stdin <<<"$(starship init bash --print-full-init)"
            fi
        }
        __main
        unset -f __main
    fi
}

# If not running interactively, don't do anything
# [[ $- = *i* ]] && load_starship || return
# load_starship

function check_sudo () {
    [[ $(whoami) != root ]] && error_msg "Please run script as root or sudo" 13
    warning_msg "Note: to run sudo and preserve passed env variables run with 'sudo -E'"
}

# Yes no prompt
function yes_no_prompt() {
    # $1 - Space separated string for prompt
    # Sets $Y_N to:
    # 0 - yes
    # 1 - no
    local yes_no_finish=1
    while [ $yes_no_finish -ne 0 ]; do
        read -p "${GREEN}${BOLD}${1} ${YELLOW}${BOLD}y/n${CLEAR}:" Y_N
        case $Y_N in
            y|Y|yes) yes_no_finish=0 && Y_N=0 ;;
            n|N|no) yes_no_finish=0 && Y_N=1 ;;
            *) echo "${RED}${BOLD}[X] ${Y_N} is not a yes/no option!" ;;
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

# Nmap scanner and report generation
function nmap-gen() {
    # $1 - IP range
    # $2 - report name

    [ -x "$(command -v nmap)" ] || error_msg "nmap not installed!" 1
    [ -x "$(command -v xsltproc)" ] || error_msg "xsltproc not installed!" 1

    [[ -n $1 ]] && local ip_range=$1 || local ip_range="192.168.1.0/24"
    [[ -n $2 ]] && local scan_name=$2 || local scan_name=nmap_scan

    info_msg "IP range: $ip_range"
    info_msg "Scan name: $scan_name"

    nmap -sTV -A -oX $scan_name.xml --webxml $ip_range && xsltproc $scan_name.xml -o $scan_name.html && rm $scan_name.xml
}

# Interval command
function do-interval() {
    # do-interval 1
    # $1 - interval in seconds 
    # $2-n - command and any number of arguments to execute
    [[ $# -lt 2 ]] && error_msg "do-interval accepts no less than 2 arguments, passed $#" 22
    [[ $1 == ?(-)+([[:digit:]]) ]] || error_msg "$1 is not a number" 22
    watch -n $1 -d=cumulative ${@:2}
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

# Attach to tmux session on shell login
function start_tmux() {
    if type tmux &> /dev/null; then
        # Check if term is inside an IDE or other environments
        # If so, do not enter a tmux session
        [[ -n "$TERM_PROGRAM" && "$TERM_PROGRAM" = @(vscode|my_ide_name) ]] && local no_tmux=true
        # Check if inside a SSH session
        [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]] && local no_tmux=true

        #if not inside a tmux session, and if no session is started, start a new session
        if [[ -z "$TMUX" && -z $TERMINAL_CONTEXT && -z "$no_tmux" ]]; then
            (tmux -2 attach || tmux -2 new-session)
        fi
    fi
}

start_tmux
