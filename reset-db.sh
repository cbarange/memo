#!/bin/bash

MAINTAINER="cbarange <cbarange@email.com>"
VERSION="0.1.0"

# Date: June 28, 2024
# 
# Changelog:
# - 2024/06/28: First version of the script
# - 2025/05/10: Add pv during the backup load
# 
# Description: 
# This script is used by developer dev to reset their local database 
# from the backups available from a FTP server. You can adjust the variable $DEFAULT_MAX_DAYS
# as needed to don't download backup if you have already one enough recent localy
# 
# Prerequisites:
# - You must have a valid ssh config to connect to $FTP_CONNECTION_STRING
# - You must install mysql command and configure variable $MYSQL_* to establish connection
# 
# Usage:
# ./reset-db.sh --help
# 
# All needed command:
# mysql(only client), sftp, cd, dirname, pwd, date(gdate on macos), awk, sed


# --- ENV ---
# Check the load_end function to get the list of all env variable that you should put in the .env file
# FROM THE .env file add and adjust this variable or use the commande 'reset_db.sh --init-setup'
DB_DIRECTORY=/home/user/bdd
MYSQL_HOST=127.0.0.1
MYSQL_USER=user
MYSQL_PASSWORD=password
MYSQL_DATABASE=database
MYSQL_PORT=3306
DEFAULT_MAX_DAYS=15

# --- VAR ---

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TODAY=$(date '+%s')
# - /!\ - DONT TOUCH THIS PART - /!\ -
BACKUP_FILENAME_PATERN="*_backup_*.bak"
PROD_BACKUP_FILENAME_PATERN="prod_backup_*.bak"
OBFUSCATED_BACKUP_FILENAME_PATERN="obfuscated_backup_*.bak"
CURRENT_BACKUP_FILENAME_PATERN="$OBFUSCATED_BACKUP_FILENAME_PATERN"


# --- UTIL FUNCTION ---

safe_tput() { [[ -n "$TERM" && "$TERM" != "dumb" ]] && tput "$@"; }

logger() {
    # Color list : https://robotmoon.com/256-colors/
    # 0: Black, 1: Red, 2: Green, 3: Yellow, 4: Blue, 5: Magenta, 6: Cyan, 7: White, 
    # 8: Bright Black (Gray), 9: , Bright Red, 10: Bright Green, 11: Bright Yellow, 
    # 12: Bright Blue, 13: Bright Magenta, 14: Bright Cyan, 15: Bright White
    local GREEN=$(safe_tput setaf 2)
    local NORMAL=$(safe_tput sgr0)
    local BLUE=$(safe_tput setaf 4)
    local RED=$(safe_tput setaf 1)
    local YELLOW=$(safe_tput setaf 3)
    local type="$1"; shift
    # accept argument string or stdin
    local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
    local dt="$(date '+%Y-%m-%d %H:%M:%S')";
    if [ "$type" == "INFO" ];then
        printf "${GREEN}[%s]${GREEN} ${BLUE}[%s]${BLUE}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    elif [ "$type" == "WARN" ];then
        printf "${GREEN}[%s]${GREEN} ${YELLOW}[%s]${YELLOW}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    elif [ "$type" == "DEBUG" ];then
        printf "${GREEN}[%s]${GREEN} ${GREEN}[%s]${GREEN}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    else
        printf "${GREEN}[%s]${GREEN} ${RED}[%s]${RED}${NORMAL}: %s\n${NORMAL}" "$dt" "$type" "$text"
    fi
}

info() { logger INFO "$@"; }
debug() { if [ "$LOGGING" = "DEBUG" ]; then logger DEBUG "$@";  fi; }
NUMBER_OF_WARN=0; warn() { logger WARN "$@" >&2;NUMBER_OF_WARN=$((NUMBER_OF_WARN+1)); }
error() { logger ERROR "$@" >&2 ; }
critical() { logger CRITICAL "$@" >&2 ; logger CRITICAL "Exiting" >&2 ; exit 1; }

# check if this file is being run or sourced from another script
_is_sourced() {
    # https://unix.stackexchange.com/a/215279
    [ "${#FUNCNAME[@]}" -ge 2 ] && [ "${FUNCNAME[0]}" = '_is_sourced' ] && [ "${FUNCNAME[1]}" = 'source' ]
}

load_env() {
    # This will overwrite system env variable
    CONFIG="${DIR}/.env"
    info "Loading env file"
    if ! [[ -f "$CONFIG" ]]; then
        warn "Config file not found, trying with env variables"
    fi
    # Load Environment Variables
    export $(cat "$CONFIG" | grep -v '#' | awk '/=/ {print $1}' | sed -e "s/'//g") &> /dev/null

    if [[ -z "$DB_DIRECTORY" || -z "$FTP_CONNECTION_STRING" || -z "$MYSQL_HOST" || -z "$MYSQL_USER" || -z "$MYSQL_PASSWORD" || -z "$MYSQL_DATABASE" || -z "$MYSQL_PORT" ]]
    then
        critical <<-'EOF'
            Missing environment variables:
                You need to specify the followings variables:
                - DB_DIRECTORY
                - FTP_CONNECTION_STRING
                - MYSQL_HOST
                - MYSQL_USER
                - MYSQL_PASSWORD
                - MYSQL_DATABASE
                - MYSQL_PORT
        EOF
    fi
}


# --- CORE FUNCTION ---

help() {
    # Display Help
    echo "$(tput setaf 2)Local Backups Management help$(tput sgr0)"
    echo
    echo "Syntax:"
    echo "reset_db [h|--manual|--latest|--max-days <int>|--help]"
    echo
    echo "Options:"
    echo "-l|--list            List local and remote backup"
    echo "--clear              Remove all matching patterns backup"
    echo "--manual             Allow user to select which backup should be load"
    echo "--latest             Force download of the latest backup"
    echo "--max-days <int>     Only download backups if any local one is old than the number of day given as argument"
    echo "--check-db           Check database connection based on env variable"
    echo "--init-setup         Initialize env file based on question from the shell"
    echo "--no-obfuscation     Allow you to access to no-obfuscated prod backups (arg must be place before other args)"
    echo "-h|--help            Print help"
    echo    
    echo "Example:"
    echo "./reset_db.sh # Load latest local backup not older than $DEFAULT_MAX_DAYS otherwise download latest from FTP"
    echo "./reset_db.sh --latest # Download & load the latest backup available from the FTP"
    echo "./reset_db.sh --max-days 90 # Load latest local backup not older than 90 days ago otherwise download the last one from the FTP"
    echo
}

check_db() {
    SQL_NUMBER_OF_TABLE=$(mysql --port="$MYSQL_PORT" --host="$MYSQL_HOST" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -B -N -e "SELECT COUNT(*) FROM information_schema.tables;")
    if [ -z "$SQL_NUMBER_OF_TABLE" ] || [ "$SQL_NUMBER_OF_TABLE" -eq 0 ] ; then
        critical "Unable to establish connection to databases with MYSQL_HOST=$MYSQL_HOST MYSQL_PORT=$MYSQL_PORT MYSQL_USER=$MYSQL_USER MYSQL_DATABASE=$MYSQL_DATABASE ❌"
    else
        info "Database connection established ($SQL_NUMBER_OF_TABLE tables retrieved from schema:$MYSQL_DATABASE) ✅"
    fi
}

download_latest_backup() {
    info "Downloading latest backup from $FTP_CONNECTION_STRING..."
    FILENAME=$(basename "$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /daily/$CURRENT_BACKUP_FILENAME_PATERN" | sed '1d' | head -n 1 | awk '{print $9}' )")
    sftp $FTP_CONNECTION_STRING:/daily/$FILENAME "$DB_DIRECTORY/$FILENAME"
}

get_last_remote_backup() {
    if [[ -z $1 ]] ; then 
        HEAD=1
    else
        HEAD=$1
    fi
    printf "%s" "$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /daily/$CURRENT_BACKUP_FILENAME_PATERN" | sed '1d' | head -n $HEAD | awk '{print $9}')"
}

get_last_local_backup() {
    if [[ -z $1 ]] ; then 
        HEAD=1
    else
        HEAD=$1
    fi
    printf "%s" "$(ls -lt $DB_DIRECTORY/$CURRENT_BACKUP_FILENAME_PATERN 2>/dev/null | head -n $HEAD | awk '{print $9}')"
}

get_last_local_backup_not_older_than() {
    # $1 int : max number of day age of local backup

    LATEST_BACKUP="$(get_last_local_backup)"
    if [[ -z $LATEST_BACKUP ]] ; then
        printf "%s" ""
        return 0
    fi

    IFS='_' read -ra BACKUP_FILEPATH <<< "$LATEST_BACKUP"
    BACKUP_DATE="${BACKUP_FILEPATH[2]%.*}"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        BACKUP_DATE=$(date -j -f "%Y-%m-%d" "$BACKUP_DATE" '+%s')
    else
        BACKUP_DATE=$(date -d "$BACKUP_DATE" '+%s')
    fi

    if [ $(( (TODAY - BACKUP_DATE) / (60*60*24) )) -gt $1 ]; then
        printf "%s" ""
    else
        printf "%s" "$LATEST_BACKUP"
    fi
}

reset_database_with() {
    # $1 FILEPATH to bak file eg: /home/user/bdd/prod_backup_2024-06-14.bak

    check_db

    info "--- DROP DATABASE ---"
    mysql --port="$MYSQL_PORT" \
        --host="$MYSQL_HOST" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        -e "DROP DATABASE IF EXISTS $MYSQL_DATABASE;"

    mysql --port="$MYSQL_PORT" \
        --host="$MYSQL_HOST" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        -e "CREATE DATABASE $MYSQL_DATABASE;"
    
    info "--- LOAD DATABASE : $1 ---"
    info "🔧 Replacing utc_timestamp() → CURRENT_TIMESTAMP...(mariadb and old mysql compliance)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/utc_timestamp()/CURRENT_TIMESTAMP/g' "$1"
      sed -i '' 's/curdate()/(CURDATE())/g' "$1"
    else
      sed -i 's/utc_timestamp()/CURRENT_TIMESTAMP/g' "$1"
      sed -i 's/curdate()/(CURDATE())/g' "$1"
    fi

    pv "$1" | mysql --port="$MYSQL_PORT" \
        --host="$MYSQL_HOST" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        $MYSQL_DATABASE
        #$MYSQL_DATABASE < "$1"

    info "--- REPLACE ALL PASSWORDS BY 'toto' ---"
        mysql --port="$MYSQL_PORT" \
        --host="$MYSQL_HOST" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        $MYSQL_DATABASE -e "update user set password = 'pbkdf2:sha256:260000\$fumJZnDZjf3JtyG9\$88dfbe23f37f0f384b0fd50521cd38a6681fe6b08f149c54bf995ed2ffca98a9'"

    echo
}

# --- MAIN ---
_main() {
    # info "Entrypoint script for Local Backup Managment"
    
    if [[ $# -eq 0 ]] ; then
        load_env
        BACKUP_FILEPATH=$(get_last_local_backup_not_older_than $DEFAULT_MAX_DAYS)
        if [[ -z $BACKUP_FILEPATH ]] ; then
            download_latest_backup
            BACKUP_FILEPATH=$(get_last_local_backup)
        fi
        reset_database_with "$BACKUP_FILEPATH"
        exit 0
    fi

    while [[ $# -gt 0 ]] ; do
        arg="$1"
        case $arg in
            --no-obfuscation)
                warn "You disable the obfuscation, please be cautious about the usage of the no-obfuscated data"
                CURRENT_BACKUP_FILENAME_PATERN="$PROD_BACKUP_FILENAME_PATERN"
                shift
            ;;
            --check-db)
                load_env
                check_db
                shift
            ;;
            --list|-l)
                load_env
                info "Here is the 10 lastest local backup"
                get_last_local_backup 10
                echo
                info "Here is the 10 lastest remote backup"
                get_last_remote_backup 10
                echo
                shift
            ;;
            --init-setup)
                init_setup
                shift
            ;;
            --clear)
                load_env
                rm $DB_DIRECTORY/$BACKUP_FILENAME_PATERN
                shift
            ;;
            --latest)
                load_env
                download_latest_backup
                BACKUP_FILEPATH=$(get_last_local_backup)
                reset_database_with "$BACKUP_FILEPATH"
                shift
                exit 0
            ;;
            --manual)
                load_env
                LOCAL_BACKUPS="$(get_last_local_backup 9)"
                if [[ -z $LOCAL_BACKUPS ]] ; then
                    read -p "$(info "There is no local backup in folder: $DB_DIRECTORY do you want to download one ? y/n")" DOWNLOAD_ANSWER
                    if [[ "$DOWNLOAD_ANSWER" == "y" || "$DOWNLOAD_ANSWER" == "yes"  ]] ; then
                        download_latest_backup
                        BACKUP_FILEPATH=$(get_last_local_backup)
                        reset_database_with "$BACKUP_FILEPATH"
                    fi
                else
                    INDEX=1
                    LOCAL_BACKUPS_ARRAY=()
                    echo
                    echo "0. Download latest from FTP"
                    while IFS=$'' read -r BACKUP_PATH; do
                        echo "$INDEX. $BACKUP_PATH"
                        LOCAL_BACKUPS_ARRAY+=($BACKUP_PATH)
                        INDEX=$((INDEX + 1))
                    done <<< "$LOCAL_BACKUPS"   
                    echo
                    read -p "$(info "Please enter the index of the backup you want to load : ")" BACKUP_INDEX

                    if [[ "$BACKUP_INDEX" -ge 1 ]] && [[ "$BACKUP_INDEX" -lt "$INDEX" ]] && [[ "$BACKUP_INDEX" =~ ^[0-9]+$ ]] ; then
                        BACKUP_FILEPATH="${LOCAL_BACKUPS_ARRAY[$((BACKUP_INDEX - 1))]}"
                        reset_database_with "$BACKUP_FILEPATH"
                    elif [[ "$BACKUP_INDEX" -eq 0 ]] && [[ "$BACKUP_INDEX" =~ ^[0-9]+$ ]] ; then
                        download_latest_backup
                        BACKUP_FILEPATH=$(get_last_local_backup)
                        reset_database_with "$BACKUP_FILEPATH"
                    else
                        critical "Invalid selection"
                    fi
                fi
                shift
                exit 0
            ;;
            --max-days)
                load_env
                shift
                BACKUP_FILEPATH=$(get_last_local_backup_not_older_than $1)
                if [[ -z $BACKUP_FILEPATH ]] ; then
                    info "No local backup not older than $1 found, starting download... "
                    download_latest_backup
                    BACKUP_FILEPATH=$(get_last_local_backup)
                fi
                reset_database_with "$BACKUP_FILEPATH"
                shift
                exit 0
            ;;
            *)
                help
                exit 0
            ;;
        esac
    done
}

if ! _is_sourced; then
    _main "$@"
fi


# --- OTHER ---
init_setup() {
    # Prompt for backup directory
    local default_dir="/tmp"
    echo "Where do you want to store the backup? Press enter to apply default (${default_dir}):"
    read -r DB_DIRECTORY
    DB_DIRECTORY=${DB_DIRECTORY:-$default_dir}  # Use default if input is empty
    # Check if the directory exists, if not, create it
    if [ ! -d "$DB_DIRECTORY" ]; then
        mkdir -p "$DB_DIRECTORY" 2>/dev/null
        if [ $? -ne 0 ]; then
            critical "Error: Failed to create directory $DB_DIRECTORY"
        fi
    fi
    info "Backup directory set to: $DB_DIRECTORY"
    echo
    # Prompt for database port
    while true; do
        echo "What's the Database port?"
        read -r MYSQL_PORT
        if [ -n "$MYSQL_PORT" ]; then
            break
        else
            warn "Database port cannot be empty. Please try again."
        fi
    done
    info "Database port set to: $MYSQL_PORT"
    echo
    # Prompt for MYSQL_HOST
    while true; do
        echo "What's the Database host? (eg: 127.0.0.1, never use 'localhost')"
        read -r MYSQL_HOST
        if [ -n "$MYSQL_HOST" ]; then
            break
        else
            warn "Database host cannot be empty. Please try again."
        fi
    done
    info "Database host set to: $MYSQL_HOST"
    echo
    # Prompt for MYSQL_USER
    while true; do
        echo "What's the Database user? (eg: app_name)"
        read -r MYSQL_USER
        if [ -n "$MYSQL_USER" ]; then
            break
        else
            warn "Database user cannot be empty. Please try again."
        fi
    done
    info "Database user set to: $MYSQL_USER"
    echo
    # Prompt for MYSQL_PASSWORD
    while true; do
        echo "What's the Database password? (eg: app_password)"
        read -r MYSQL_PASSWORD
        if [ -n "$MYSQL_PASSWORD" ]; then
            break
        else
            warn "Database password cannot be empty. Please try again."
        fi
    done
    info "Database password set to: $MYSQL_PASSWORD"
    echo
    # Prompt for MYSQL_DATABASE
    while true; do
        echo "What's the Database name? (eg: app_name)"
        read -r MYSQL_DATABASE
        if [ -n "$MYSQL_DATABASE" ]; then
            break
        else
            warn "Database name cannot be empty. Please try again."
        fi
    done
    info "Database name set to: $MYSQL_DATABASE"

    # Display final configuration
    echo "" >> "${DIR}/../.env"
    echo "# --- RESET DB SCRIPT ENV AUTOCOMPLETED ON $(date '+%Y-%m-%d') ---" >> "${DIR}/../.env"
    echo "DB_DIRECTORY=$DB_DIRECTORY" >> "${DIR}/../.env"
    echo "MYSQL_HOST=$MYSQL_HOST" >> "${DIR}/../.env"
    echo "MYSQL_USER=$MYSQL_USER" >> "${DIR}/../.env"
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> "${DIR}/../.env"
    echo "MYSQL_DATABASE=$MYSQL_DATABASE" >> "${DIR}/../.env"
    echo "MYSQL_PORT=$MYSQL_PORT" >> "${DIR}/../.env"
    echo "DEFAULT_MAX_DAYS=15" >> "${DIR}/../.env"
    echo "# --- === ---" >> "${DIR}/../.env"
    load_env

    check_db
}
