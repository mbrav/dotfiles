#!/bin/bash

# COLORS
ncolors=$(command -v tput > /dev/null && tput colors) # supports color
if [[ -n $ncolors && -z $NO_COLOR ]]; then
    TERMCOLS=$(tput cols)
    CLEAR="$(tput sgr0)"

    # 4 bit colors
    if test $ncolors -ge 8; then
        # Normal
        BLACK="$(tput setaf 0)"
        RED="$(tput setaf 1)"
        GREEN="$(tput setaf 2)"
        YELLOW="$(tput setaf 3)"
        BLUE="$(tput setaf 4)"
        MAGENTA="$(tput setaf 5)"
        CYAN="$(tput setaf 6)"
        GREY="$(tput setaf 7)"
    fi

    # >4 bit colors
    if test $ncolors -gt 8; then
        # High intensity
        BLACK_I="$(tput setaf 8)"
        RED_I="$(tput setaf 9)"
        GREEN_I="$(tput setaf 10)"
        YELLOW_I="$(tput setaf 11)"
        BLUE_I="$(tput setaf 12)"
        MAGENTA_I="$(tput setaf 13)"
        CYAN_I="$(tput setaf 14)"
        WHITE="$(tput setaf 15)"
    else
        BLACK_I=$BLACK
        RED_I=$RED
        GREEN_I=$GREEN
        YELLOW_I=$YELLOW
        BLUE_I=$BLUE
        MAGENTA_I=$MAGENTA
        CYAN_I=$CYAN
        WHITE=$GREY
    fi

    # Styles
    UNDERLINE="$(tput smul)"
    STANDOUT="$(tput smso)"
    BOLD="$(tput bold)"
fi

COLORS=("$BLACK" "$RED" "$GREEN" "$YELLOW" "$BLUE" "$MAGENTA" "$CYAN" "$GREY" "$BLACK_I" "$BLACK_I" "$RED_I" "$GREEN_I" "$YELLOW_I" "$BLUE_I" "$MAGENTA_I" "$CYAN_I" "$WHITE")
STYLES=("$UNDERLINE" "$BOLD")

function r_color () {
    # Set a random color
    echo -e -n "${COLORS[RANDOM%${#COLORS[@]}]}"
}

function r_color_st () {
    # Set a random color with style
    echo -e -n "${COLORS[RANDOM%${#COLORS[@]}]}${STYLES[RANDOM%${#STYLES[@]}]}"
}

function error_msg() {
    # Error message
    # $1            - Message string argument
    # $2 (optional) - exit code
    echo -e "${RED}${BOLD}[X] ${1}${CLEAR}"
    [[ -n $2 ]] && exit $2
}

function warning_msg() {
    echo -e "${YELLOW}${BOLD}[!] ${*}${CLEAR}"
}

function success_msg() {
    echo -e "${GREEN}${BOLD}[✓] ${*}${CLEAR}"
}

function info_msg() {
    echo -e "${CYAN}[i] ${*}${CLEAR}"
}

# echo -e -n "$(r_color_st)L$(r_color)O$(r_color)A$(r_color_st)D$(r_color)E$(r_color_st)D$CLEAR "
# echo -e -n "$(r_color_st)T$(r_color)E$(r_color)R$(r_color_st)M$(r_color)I$(r_color_st)N$(r_color)A$(r_color_st)L$CLEAR "
# echo -e "$(r_color_st)C$(r_color)O$(r_color)L$(r_color_st)O$(r_color)R$(r_color_st)S$CLEAR "


function load_starship () {
    # Load starship prompt if starship is installed
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

function check_sudo () {
    [[ $(whoami) != root ]] && error_msg "Please run script as root or sudo" 13
    warning_msg "Note: to run sudo and preserve passed env variables run with 'sudo -E'"
}

function yes_no_prompt() {
    # Yes no prompt
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

function check_url() {
    # Check for passed url
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

function replace-vars() {
    # Replace text and show interactive
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

function dock-save() {
    # Save docker images
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo -e $RED"Must provide 2 arguments, docker image name and tar output file name (no exension)"$CLEAR
        exit 1
    fi
    mkdir -p ~/docker-images
    echo -e $GREEN"Exporting image $YELLOW$1 $GREEN to ~/docker-images/$YELLOW$2.tar.gz"$CLEAR
    docker save $1 | gzip -c > ~/docker-images/$2.tar.gz
}

function _dock-save_completions() {
    # Auto completion for docker-save
    [ "${#COMP_WORDS[@]}" != "2" ] && return || \
        COMPREPLY=($(compgen -W "$(docker images --format "{{.Repository}}:{{.Tag}}")" "${COMP_WORDS[1]}"))
}

complete -F _dock-save_completions dock-save

function nmap-gen() {
    # Nmap scanner and report generation
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

function 7z-max() {
    # Max 7z compression
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

# wakatime for bash
#
# include this file in your "~/.bashrc" file with this command:
#   . path/to/bash-wakatime.sh
#
# or this command:
#   source path/to/bash-wakatime.sh
#
# Don't forget to create and configure your "~/.wakatime.cfg" file.

# hook function to send wakatime a tick
pre_prompt_command() {
    version="1.0.0"
    entity=$(echo $(fc -ln -0) | cut -d ' ' -f1)
    [ -z "$entity" ] && return # $entity is empty or only whitespace
    $(git rev-parse --is-inside-work-tree 2> /dev/null) && local project="$(basename $(git rev-parse --show-toplevel))" || local project="Terminal"
    (~/.wakatime/wakatime-cli --write --plugin "bash-wakatime/$version" --entity-type app --project "$project" --entity "$entity" 2>&1 > /dev/null &)
}

PROMPT_COMMAND="pre_prompt_command; $PROMPT_COMMAND"

function start_tmux() {
    if ! command -v tmux &> /dev/null; then
        # Check if tmux is installed
        # if not, exit function
        echo "🛑 Tmux not installed, not starting tmux session"
        return
    fi

    if [ -n "$TMUX" ]; then
        # Check if already inside tmux
        # if so, exit function
        return
    fi

    # Set default session name to "main"
    tmux_session_name="🐺main"

    if [[ -n "$TERM_PROGRAM" && "$TERM_PROGRAM" = @(vscode|my_ide_name) ]]; then
        # Check if term is inside an IDE or other environments
        project_folder="$(pwd)"
        project_folder_name="$(basename $project_folder)"
        tmux_session_name="🖥️$project_folder_name"
    fi

    if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" || -n "$project_folder" ]]; then
        # Check if inside a SSH session
        # And if not inside a term program in cases where VScode Server is used
        # If so, do not enter a tmux session and exit function
        echo "🛑 Inside SSH session, not starting tmux session"
        return
    fi

    # Attach to existing or create a new tmux session
    if [ -n "$(tmux ls | grep "$tmux_session_name")" ]; then
        echo "🚪 Tmux session '$tmux_session_name' exists, entering"
    else
        echo "🪄 Tmux session '$tmux_session_name' does not exist, creating"
    fi
    tmux -2 attach -t "$tmux_session_name" || tmux -2 new-session -s "$tmux_session_name"
}

start_tmux
