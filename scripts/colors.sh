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
