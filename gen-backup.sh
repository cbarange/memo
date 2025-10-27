#!/bin/bash

MAINTAINER="cbarange <cbarange@email.com>"
VERSION="0.1.0"

# Date: March 25, 2024
# 
# Changelog:
# - 2024/07/25: First version of the script
# - 2025/05/10: Implement a second credentials for the obfuscate database
# 
# Description: 
# This script backup a MySQL database $MYSQL_HOST as a full sql file and upload this file
# to a FTP server $FTP_CONNECTION_STRING. The FTP server should have a chroot user with 
# this 3 folders /daily, /weekly and /monthly. This script also allow you to generate a
# obfuscated backup file. Check the obfuscate.sql file to see how it's work. Please read and
# adjust the --- CONFIG --- section. This script is design to run on a server as a cron job.
# Here is a example of a crontab line to run the script at 4:30 AM
# 30 04 * * * bash /home/user/gen-backup.sh &>>/home/user/logs/archives/gen-backup-$(date +\%F).log
# 
# Usage:
# bash gen-backup.sh    # Generate & Upload db backup
# bash gen-backup.sh -l # List FTP FILES
# 
# All needed command:
# mysql(only client), mysqldump, sftp, cd, dirname, pwd, date(gdate on macos), awk, sed


# --- CONFIG ---

DAILY_DAYS_RETENTION=15 # retention days for the folder /daily
WEEKLY_DAYS_RETENTION=45 # retention days for the folder /weekly
MONTHLY_DAYS_RETENTION=180 # retention days for the folder /monthly

DIRPATH="/home/user/foo" # Folder use to store the SQL backup.dump file

FTP_CONNECTION_STRING="sftp_user@backup.example.com" # You should have configure a ssh key

# MySQL Credential use to generate the backup
MYSQL_HOST="10.4.3.2"
MYSQL_DATABASE="database_name"
MYSQL_USER="sql_user"
MYSQL_PASSWORD="password"

# MySQL Credential use to generate the obfuscated backup. Can be the same MySQL 
# server as the previous one or a different, using a different one will not 
# overload your main MySQL server, as the obfuscation can use many resource (CPU & RAM)
MYSQL_OBFUSCATED_DATABASE="obfuscated_database"
MYSQL_OBFUSCATED_USER="user"
MYSQL_OBFUSCATED_HOST="127.0.0.1"
MYSQL_OBFUSCATED_PASSWORD="password"
MYSQL_OBFUSCATED_PORT="3306"

# Don't forget to allow ALL PRIVILEGES the $MYSQL_OBFUSCATED_USER, he will need them
# to load the normal backup into the $MYSQL_OBFUSCATED_DATABASE
# CREATE USER 'user'@'%' IDENTIFIED BY 'password';
# GRANT ALL PRIVILEGES ON obfuscated_database.* TO 'user'@'%' WITH GRANT OPTION;
# FLUSH PRIVILEGES;


# --- VAR ---
TODAY=$(date '+%s')
FILENAME="prod_backup_$(date '+%Y-%m-%d').bak"
OBFUSCED_FILENAME="obfuscated_backup_$(date '+%Y-%m-%d').bak"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SQL_OBFUSCATE_FILEPATH="$DIR/obfuscate.sql"


# --- FUNCTION ---

history_retention(){
    # Remove file created more than $1 days ago from directory $3 for each line from $2
    # $1 : DAYS_RETENTION
    DAYS_RETENTION=$1
    # $2 : FILES from $(ls -lt)
    FILES="$2"
    # $3 : PATH from ftp
    FTP_PATH="$3"

    if [[ -z "$FILES" ]]; then
        echo "No file under $FTP_PATH"
        return 0
    fi

    echo "$FILES" | awk '{print $6, $7, $8, $9}' | while read -r month day time file; do        
        FILE_CREATION_DATE=$(date -d "$month $day $time" '+%s')
        # Calculate the difference in days
        diff_days=$(( (TODAY - FILE_CREATION_DATE) / (60*60*24) ))
        
        # Check if the file is more than DAYS_RETENTION days old
        if [ $diff_days -gt $DAYS_RETENTION ]; then
            echo "Removing $FTP_PATH/$file created more than $DAYS_RETENTION days ago."
            sftp -b - $FTP_CONNECTION_STRING <<< "rm $FTP_PATH/$file"
        else
            echo "Keeping $FTP_PATH/$file (created $diff_days days ago)."
        fi
    done 
}


list() {
    echo "DAILY"
    echo "$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /daily" | sed '1d')"
    echo
    echo "WEEKLY"
    echo "$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /weekly" | sed '1d')"
    echo
    echo "MONTHLY"
    echo "$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /monthly" | sed '1d')"
    echo
}

create_local_backup() {
    # --- CREATE THE BACKUP AND SAVE IT LOCALY ---
    echo "Create backup for database $MYSQL_DATABASE"
    mysqldump --skip-column-statistics --column-statistics=0 --set-gtid-purged=OFF -u $MYSQL_USER -h $MYSQL_HOST -p$MYSQL_PASSWORD $MYSQL_DATABASE > "$DIRPATH/$FILENAME"
    # --- ==================================== ---
}

upload() {
    # --- UPLOAD BACKUP TO THE SFTP ---
    # FTP Folder : /daily /weekly /monthly
    echo "Uploading daily backup"
    sftp -b - $FTP_CONNECTION_STRING <<< "put $DIRPATH/$FILENAME /daily/$FILENAME"
    if [ $(date -d @$TODAY +%u) -eq 7 ]; then
        echo "We are Sunday, uploading weekly backups"
        sftp -b - $FTP_CONNECTION_STRING <<< "put $DIRPATH/$FILENAME /weekly/$FILENAME"
    fi

    if [ $(date -d @$TODAY +%d) -eq 01 ]; then
        echo "We are the 1rst of the month, uploading monthly backups"
        sftp -b - $FTP_CONNECTION_STRING <<< "put $DIRPATH/$FILENAME /monthly/$FILENAME"
    fi
    # --- ========================= ---
}

remove_old_backups() {
    # --- REMOVE OLD BACKUP ---
    # Daily
    DAILY_FILES="$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /daily" | sed '1d')"
    if [[ -z "$DAILY_FILES" ]]; then
        echo "No file under /daily"
    else
        history_retention $DAILY_DAYS_RETENTION "$DAILY_FILES" "/daily"
    fi
    
    # Weekly
    WEEKLY_FILES="$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /weekly" | sed '1d')"
    if [[ -z "$WEEKLY_FILES" ]]; then
        echo "No file under /weekly"
    else
        history_retention $WEEKLY_DAYS_RETENTION "$WEEKLY_FILES" "/weekly"
    fi
    
    # Monthly
    MONTHLY_FILES="$(sftp -q -b - $FTP_CONNECTION_STRING <<< "ls -lt /monthly" | sed '1d')"
    if [[ -z "$MONTHLY_FILES" ]]; then
        echo "No file under /monthly"
    else
        history_retention $MONTHLY_DAYS_RETENTION "$MONTHLY_FILES" "/monthly"
    fi
    # --- ================= ---
}

generate_obfuscated_backup() {
    echo "Loading the backup into $MYSQL_OBFUSCATED_DATABASE to run the obfuscation sql script : $SQL_OBFUSCATE_FILEPATH"
    mysql -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" \
        -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" \
        -e "DROP DATABASE IF EXISTS $MYSQL_OBFUSCATED_DATABASE;CREATE DATABASE $MYSQL_OBFUSCATED_DATABASE;"
    
    mysql -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" \
        -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" \
        $MYSQL_OBFUSCATED_DATABASE < "$DIRPATH/$FILENAME"

    echo "Running obfuscation sql script..."
    mysql -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" \
        -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" \
        $MYSQL_OBFUSCATED_DATABASE -e "SET @TABLE_SCHEMA='$MYSQL_OBFUSCATED_DATABASE';$(cat $SQL_OBFUSCATE_FILEPATH)"
    
    if [ $? -ne 0 ]; then
        # If the command failed
        echo "[ERROR] Failed to obfuscate the $MYSQL_DATABASE database, there will be no obfuscated backup available until this error has been fixed"
        mysql -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" \
            -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" \
            -e "DROP DATABASE IF EXISTS $MYSQL_OBFUSCATED_DATABASE;"
    else
        # If the command succeeded
        mysqldump --skip-column-statistics --column-statistics=0 --set-gtid-purged=OFF -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" $MYSQL_OBFUSCATED_DATABASE > "$DIRPATH/$OBFUSCED_FILENAME"
        mysql -u"$MYSQL_OBFUSCATED_USER" -P "$MYSQL_OBFUSCATED_PORT" \
            -h "$MYSQL_OBFUSCATED_HOST" -p"$MYSQL_OBFUSCATED_PASSWORD" \
            -e "DROP DATABASE IF EXISTS $MYSQL_OBFUSCATED_DATABASE;"
        sftp -b - $FTP_CONNECTION_STRING <<< "put $DIRPATH/$OBFUSCED_FILENAME /daily/$OBFUSCED_FILENAME"
    fi
}

# --- MAIN ---
_main() {
    # Manage backup rotation & retention
    create_local_backup
    upload
    remove_old_backups
    generate_obfuscated_backup
    
    # Remove local backup
    echo "Removing local backups..."
    rm "$DIRPATH/$FILENAME"
    rm "$DIRPATH/$OBFUSCED_FILENAME"
    echo "Backup History Done ✅"
}


if [[ $# -eq 0 ]] ; then
    _main
else
    list
fi

exit 0