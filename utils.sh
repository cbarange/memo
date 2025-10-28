#!/bin/bash

# Utils bash functions

remove_crontab() {
    # Remove exiting skeleton crontab
    /bin/crontab -l 2>/dev/null | grep -v "skeleton.sh --sync" | /bin/crontab -
}

enable_crontab() {
    # Add the skeleton crontab
    crontabline="10 3 * * * bash ${DIR}/skeleton.sh --sync > $LOG_DIRECTORY/skeleton-\$(date '+\%F').log 2>&1"
    /bin/crontab -l | { cat - ; echo "$crontabline"; } | /bin/crontab -
    printf "%s" "$crontabline"
}


verify_minimum_commands() {
    info "Checking minimum configuration..."
    if ! command -v jq &> /dev/null
    then
        error "jq doesn't exist, please install and allow access to the command 'jq'"
    fi
}

array_to_json() {
    # From a bash array $@
    # Convert into a Json.list [item,item1,item2]
    ARRAY=("$@")
    JSON_OBJECTS="$( IFS=$','; echo "${ARRAY[*]}" )"
    printf "%s" "[$JSON_OBJECTS]"
}


file_exists() {
  # Usage : if file_exists "/foo/bar.txt"; then ; TODO ; fi
  if [ -f "$1" ]; then
    return 0  # true
  else
    return 1  # false
  fi
}


folder_exists() {
    local folder="$1"
    if [ -d "$folder" ]; then
        return 0
    else
        return 1
    fi
}


# Function: is_user_exist
# Usage: is_user_exist username
# Returns: 0 if exists, 1 if not
is_user_exist() {
    local user="$1"
    if getent passwd "$user" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}


load_env() {
    # source ${DIR}/utils.sh # Import file

    # This will overwrite system env variable
    CONFIG="${DIR}/.env"
    info "Loading env file"
    if ! [[ -f "$CONFIG" ]]; then
        warn "Config file not found, trying with env variables"
    else
        # Load Environment Variables
        export $(cat "$CONFIG" | grep -v '#' | awk '/=/ {print $1}' | sed -e "s/'//g") &> /dev/null
    fi

    if [[ -z "$DB_NAME" || -z "$APP_USER" ]]; then
        critical <<-'EOF'
            Missing environment variables:
                You need to specify the followings variables:
                - DB_NAME
                - APP_USER
        EOF
    fi
}