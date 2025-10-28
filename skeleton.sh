#!/bin/bash

MAINTAINER="cbarange <cbarange@email.com>"
VERSION="0.0.1"

# Date: September 14, 1970
#
# Changelog:
# - 01/01/1970 : The begining
# - 25/09/2025 : ...
# 
# Description: 
# This file is a script skeleton
#
# Usage: 
# Base for new script eg: bash skeleton.sh --help

# --- BASH SETTINGS ---
#set -e # Exit immediately if a command fails
readonly SCRIPT_NAME=$(basename "$0")


# --- CONFIG ---
LOGGING="${LOGGING}" # Can be set to "DEBUG"


# --- VAR ---
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
START_TIME=$(date +%s)


# --- UTIL FUNCTION ---

# check to see if this file is being run or sourced from another script
_is_sourced() {
    # https://unix.stackexchange.com/a/215279
    [ "${#FUNCNAME[@]}" -ge 2 ] && [ "${FUNCNAME[0]}" = '_is_sourced' ] && [ "${FUNCNAME[1]}" = 'source' ]
}

safe_tput() { [[ -n "$TERM" && "$TERM" != "dumb" ]] && tput "$@"; }

logger() {
    # Color list : https://robotmoon.com/256-colors/
    # 0: Black, 1: Red, 2: Green, 3: Yellow, 4: Blue, 5: Magenta, 6: Cyan, 7: White, 
    # 8: Bright Black (Gray), 9: , Bright Red, 10: Bright Green, 11: Bright Yellow, 
    # 12: Bright Blue, 13: Bright Magenta, 14: Bright Cyan, 15: Bright White
    local GREEN=$(safe_tput setaf 2); local NORMAL=$(safe_tput sgr0)
    local BLUE=$(safe_tput setaf 4); local RED=$(safe_tput setaf 1)
    local YELLOW=$(safe_tput setaf 3); local type="$1"; shift
    # accept argument string or stdin
    local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
    local dt; dt="$(date '+%Y-%m-%d %H:%M:%S')";
    if [ "$type" == "INFO" ];then
        printf "${GREEN}[%s]${GREEN} ${BLUE}[%s]${BLUE}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    elif [ "$type" == "WARN" ];then
        printf "${GREEN}[%s]${GREEN} ${YELLOW}[%s]${YELLOW}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    elif [ "$type" == "DEBUG" ];then
        printf "${GREEN}[%s]${GREEN} ${GREEN}[%s]${GREEN}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    else # ERROR
        printf "${GREEN}[%s]${GREEN} ${RED}[%s]${RED}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    fi
}
NUMBER_OF_WARN=0; NUMBER_OF_ERROR=0;
info() { logger INFO "$@"; }
debug() { if [ "$LOGGING" = "DEBUG" ]; then logger DEBUG "$@";  fi; }
warn() { logger WARN "$@" >&2;NUMBER_OF_WARN=$((NUMBER_OF_WARN+1)); }
error() { logger ERROR "$@" >&2 ;NUMBER_OF_ERROR=$((NUMBER_OF_ERROR+1)); }
critical() { logger CRITICAL "$@" >&2 ; logger CRITICAL "Exiting" >&2 ; exit 1; }


# --- CORE FUNCTION ---
help() {
    # Display Help
    echo "$(safe_tput setaf 2)Help$(safe_tput sgr0)"
    echo
    echo "Syntax:"
    echo "skeleton.sh [--version|--debug|--foo|--help] [YYYY-MM-DD]"
    echo
    echo "Options:"
    echo "--foo            Run foo"
    echo "-h|--help        Print help"
    # echo
    # echo "Arguments:"
    # echo "[date]               Format [YYYY-MM-DD] that will use to retrieve daily stats segment, channel and scenario. Default is today date"
    echo
    echo "Example:"
    echo "./skeleton.sh --debug --foo # Run foo with debug option"
    echo "LOGGING='DEBUG' ./skeleton.sh --h # Run help with debug option"

    echo
}


# --- MAIN ---

_main() {
    # Main function, use for checking: argument, env variable, insatalled packages
    if [[ $# -eq 0 ]] ; then
        error "Argument is missing. Please check: --help"
    fi

    # info "Entrypoint script for Stats DM started."
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case $arg in
            --debug)
                LOGGING="DEBUG"
                info "mode debug enable, to disable it remove --debug"
                shift
            ;;
            --version)
                info "Version:$VERSION  Maintainer:$MAINTAINER"
                exit 0
            ;;
            --foo)
                do_something $2
                do_something $@
                shift
            ;;
            --bar)
                error "Yes error"
                exit 0
            ;;
            -h|--help)
                help
                shift
                exit 0
            ;;
            *)
                help
                shift
            ;;
        esac
    done
}


if ! _is_sourced; then
    _main "$@"
    
    info "$SCRIPT_NAME executed in $(( $(date +%s) - START_TIME))s with $NUMBER_OF_ERROR error and $NUMBER_OF_WARN warning"
    exit 0
fi
