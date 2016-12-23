#!/bin/bash

##########
#
# Script for doing a full backup of your
# ownCloud installation
#
# Christian Ploeger, 20.11.2016
#
##########

# uncomment the following line to debug this script
#set -x

# check if the target directory meets the requirements for running the script
# if it doesn't exist the script will try to create it
# this check is important because the parameter is entered by the user
check_backupdir() {
  # Check if the target directory for the backup already exists
  if [ -e "$backupdir" ]; then
    # We need to take a closer look if the target directory already exists
    # 1) Is it really a directory?
    if [ -d "$backupdir" ]; then
      # 2) Is the directory writeable?
      if [ -w "$backupdir" ]; then
        return 0
      else
        msg_error+=("The target directory you entered ('$backupdir') is not writeable.")
      fi
    else
      msg_error+=("The target directory you entered ('$backupdir') already exists but is not a directory.")
    fi
  else
    # The target directory for the backup does not exist ==> create it
    if errormsg=$(mkdir -p "$backupdir/oc-backup-$timestamp" 2>&1 >/dev/null); then
      return 0
    else
      msg_error+=("An error occured while creating the target directory you entered ('$backupdir'): $errormsg")
    fi
  fi
  return 1
}

# check if the directory where the data is stored exists and if it is readable
check_datadir() {
  # Check if the data directory exists
  if [ -e "${occonfig[0]}" ]; then
    # 1) Is it really a directory?
    if [ -d "${occonfig[0]}" ]; then
      # 2) Is the directory readable?
      if [ -r "${occonfig[0]}" ]; then
        return 0
      else
        msg_error+=("The data directory ('${occonfig[0]}') is not readable.")
      fi
    else
      msg_error+=("The data directory ('{$occonfig[0]}') exists but is not a directory.")
    fi
  else
    # As this directory is supposed to contain the data stored in your, it makes no sense to create it
    msg_error+=("The data directory ('{$occonfig[0]}') does not exist.")
  fi
  return 1
}

# check if the directory where your OwnCloud is stored exists and if it is readable
# this is important because the parameter is entered by the user
check_ocdir() {
  # Check if the installation directory exists
  if [ -e "$oc_instdir" ]; then
    # 1) Is it really a directory?
    if [ -d "$oc_instdir" ]; then
      # 2) Is the directory readable?
      if [ -r "$oc_instdir" ]; then
        return 0
      else
        msg_error+=("The installation directory you entered ('$oc_instdir') is not readable.")
      fi
    else
      msg_error+=("The installation directory you entered ('$oc_instdir') exists but is not a directory.")
    fi
  else
    # As this directory is supposed to contain the "binaries" of your ownCloud, it makes no sense to create it
    msg_error+=("The installation directory you entered ('$oc_instdir') does not exist.")
  fi
  return 1
}

cleanup_backupdir() {
  # delete the temporary backup directory
  if errormsg=$(rm -rf "$backupdir/oc-backup-$timestamp" 2>&1 >/dev/null); then
    # deletd all files older than 180 minutes
    if errormsg=$(find "$backupdir" -type f -cmin +180 -delete 2>&1 >/dev/null); then
      return 0
    else
      msg_error+=("Deleting old backups in the directory '$backupdir' failed: $errormsg")
    fi
  else
    msg_error+=("Deleting the temporary backup directory '$backupdir/oc-backup-$timestamp' failed: $errormsg")
  fi
  return 1
}

# some manipulations to exclude unneccessary files from the backup
cleanup_snapshot() {
  cd "$backupdir/oc-backup-$timestamp" || return 1
  if dirname=$(find . -mindepth 1 -maxdepth 1 -type d | cut -c3-); then
    if [ -e "$dirname/owncloud.log" ]; then
      if ! errormsg=$(rm "$dirname/owncloud.log" 2>&1 >/dev/null); then
        msg_error+=("Deleting the OwnCloud logfile failed: $errormsg")
      fi
    fi

    if [ -e "$dirname/update.log" ]; then
      if ! errormsg=$(rm "$dirname/update.log" 2>&1 >/dev/null); then
        msg_error+=("Deleting the logfile of the updater app failed: $errormsg")
      fi
    fi

    if [ -e "$dirname/updater_backup" ]; then
      if ! errormsg=$(rm -r "$dirname/updater_backup" 2>&1 >/dev/null); then
        msg_error+=("Deleting the backups of the updater app failed: $errormsg")
      fi
    fi

    if [ -e "$dirname/updater-data" ]; then
      if ! errormsg=$(rm -r "$dirname/updater-data" 2>&1 >/dev/null); then
        msg_error+=("Deleting the data of the updater app failed: $errormsg")
      fi
    fi
  else
    msg_error+=("Finding the name of the data directory within the temporaty backup directory failed.")
  fi

  if [ ${#msg_error[@]} -gt 0 ]; then
    return 1
  else
    return 0
  fi
}

create_backup() {
  # enabling maintenance mode
  if errormsg=$("$oc_instdir/occ" --no-warnings --quiet maintenance:mode --on 2>&1 >/dev/null); then
    oc_offline_start=$(date "+%d.%m.%Y %H:%M:%S")
    maintenance=true
    # data backup
    if errormsg=$(rsync -Aakx "${occonfig[0]}" "$backupdir/oc-backup-$timestamp" 2>&1 >/dev/null); then
      # cleaning up the snapshot of the data directory
      if cleanup_snapshot; then
        # config backup
        errormsg=$(rsync -Aax "$oc_instdir/config" "$backupdir/oc-backup-$timestamp" 2>&1 >/dev/null)
        if [ -z "$errormsg" ]; then
          # database backup
          errormsg=$(mkdir -p "$backupdir/oc-backup-$timestamp/db" 2>&1 >/dev/null)
          if [ -z "$errormsg" ]; then
            errormsg=$(mysqldump --defaults-extra-file="$tempdir/oc-backup-$timestamp/mysql.cnf" --lock-tables "${occonfig[2]}" > "$backupdir/oc-backup-$timestamp/db/oc-backup-$timestamp.sql" 2>&1)
            if [ -z "$errormsg" ]; then
              # disabling maintenance mode
              # can be done before creating the archive for keeping the downtime as short as possible
              errormsg=$("$oc_instdir/occ" --no-warnings --quiet maintenance:mode --off 2>&1 >/dev/null)
              if [ -z "$errormsg" ]; then
                oc_offline_end=$(date "+%d.%m.%Y %H:%M:%S")
                maintenance=false
                cd "$backupdir/oc-backup-$timestamp" || return 1
                errormsg=$(tar czf "../oc-backup-$timestamp.tar.gz" . 2>&1 >/dev/null)
                if [ -z "$errormsg" ]; then
                  return 0
                else
                  msg_error+=("An error occured while creating the archive '$backupdir/oc-backup-$timestamp.tar.gz': $errormsg")
                fi
              else
                msg_error+=("An error occured while activating maintenance mode: $errormsg")
              fi
            else
              msg_error+=("An error occured while backing up the database: $errormsg")
            fi
          else
            msg_error+=("An error occured while creating the target directory for the database: $errormsg")
          fi
        else
          msg_error+=("An error occured while backing up the config directory: $errormsg")
        fi
      else
         msg_error+=("An error occured while cleaning up the snapshot of the data directory")
      fi
    else
      msg_error+=("An error occured while backing up the data directory: $errormsg")
    fi
  else
    msg_error+=("An error occured while deactivating maintenance mode: $errormsg")
  fi
  return 1
}

# reading params from your OwnCloud
getocconfig() {
  if occonfig[0]=$("${oc_instdir}/occ" --no-warnings config:system:get datadirectory); then
    if occonfig[1]=$("${oc_instdir}/occ" --no-warnings config:system:get dbhost); then
      if occonfig[2]=$("${oc_instdir}/occ" --no-warnings config:system:get dbname); then
        if occonfig[3]=$("${oc_instdir}/occ" --no-warnings config:system:get dbpassword); then
          if occonfig[4]=$("${oc_instdir}/occ" --no-warnings config:system:get dbuser); then
            if errormsg=$(touch "$tempdir/oc-backup-$timestamp/mysql.cnf" 2>&1 >/dev/null); then
              if errormsg=$(chmod 600 "$tempdir/oc-backup-$timestamp/mysql.cnf" 2>&1 >/dev/null); then
                if cat >>"$tempdir/oc-backup-$timestamp/mysql.cnf" <<EOL
[client]
user = ${occonfig[4]}
password = ${occonfig[3]}
host = ${occonfig[1]}
EOL
                then
                  return 0
                else
                  msg_error+=("Writing the MySQL configuration into the file '$tempdir/mysql.cnf' failed.")
                fi
              else
                msg_error+=("Setting the permissions for the file for the MySQL configuration ('$tempdir/mysql.cnf') failed: $errormsg")
              fi
            else
              msg_error+=("Creating the file for the MySQL configuration ('$tempdir/mysql.cnf') failed: $errormsg")
            fi
          else
            msg_error+=("Getting the data directory by occ failed.")
          fi
        else
          msg_error+=("Getting the database server by occ failed.")
        fi
      else
        msg_error+=("Getting the database name by occ failed.")
      fi
    else
      msg_error+=("Getting the password for the database user by occ failed.")
    fi
  else
    msg_error+=("Getting the database user by occ failed.")
  fi
  return 1
}

parameter_check() {
  if [ $# -ge 3 ]; then
    oc_instdir="$1"
    backupdir="$2"
    mailRecipient="$3"
    if [ $# -gt 3 ]; then
      tempdir="$4"
    else
      tempdir="/tmp"
    fi
  else
    msg_error+=(" 4) temporary directory to use (optional)")
    msg_error+=(" 3) recipient for the results")
    msg_error+=(" 2) target directory where the backup will be stored")
    msg_error+=(" 1) the installation directory of our ownCloud (e.g. /var/www/)")
    msg_error+=("This script needs at least three parameters:")
    return 1
  fi
  return 0
}

# start of the main script
tsp_start=$(date "+%s")
timestamp=$(date --date="@$tsp_start" "+%Y%m%d_%H%M")

# initialization of the array that stores error messages
msg_error=()

# maintenance mode is supposed to be off
maintenance=false

# check if the user entered the right number of parameters
if parameter_check "$@"; then
  # create temporary directory
  if errormsg=$(mkdir -p "$tempdir/oc-backup-$timestamp" 2>&1 1>/dev/null); then
    if check_backupdir; then
      # creating a lockfile to prevent that the script runs mutiple times at once
      lockfile="$backupdir/oc-maintenance.lock"
      # check if there's still a lockfile from a previous run that failed
      if [ -e "$lockfile" ]; then
        msg_error+=("There's still a lockfile in the target directory. Please check what went wrong when this script was run for the last time.")
      else
        date=$(date --date="@$tsp_start" "+%d.%m.%y")
        time=$(date --date="@$tsp_start" "+%H:%M:%S")
        echo -e "Script last started: $date $time." > "$lockfile"
        if check_ocdir; then
          cur_user=$(whoami)
          oc_user=$(stat -c '%U' "$oc_instdir/occ")
          # check if the script runs as the user as ownCloud does
          if [ "$cur_user" == "$oc_user" ]; then
            if getocconfig; then
              if check_datadir; then
                if create_backup; then
                  cleanup_backupdir
                else
                  msg_error+=("Creating the backup failed.")
                fi
              fi
            fi
          fi
        else
          msg_error+=("The script has to be run as '$oc_user'. You tried to run it as '$cur_user'.")
        fi
      fi
    fi
  else
    msg_error+=("Creating the temporary directory '$tempdir' failed: $errormsg")
  fi
fi

# turn maintenance mode off if it is still active
if [ $maintenance == true ]; then
  errormsg=$("$oc_instdir/occ" --no-warnings --quiet maintenance:mode --off 2>&1 >/dev/null)
  if [ -n "$errormsg" ]; then
    msg_error+=("!!! WARNING: YOUR OWNCLOUD INSTALLATION IS STILL IN MAINTENANCE MODE AND CANNOT BE ACCESSED !!!")
    msg_error+=("Error occured while turning off maintenance mode: $errormsg")
  fi
fi

num_error=${#msg_error[@]}
if [ "$num_error" -eq 0 ]; then
  rm "$lockfile"
  backup_start=$(date --date="@$tsp_start" "+%d.%m.%Y %H:%M:%S")
  backup_end=$(date "+%d.%m.%Y %H:%M:%S")

  echo -e "ownCloud backup on host '$(hostname -f)' finished successfully." > "$tempdir/oc-backup-$timestamp/oc-message.txt"
  {
    echo -e "\n"
    echo -e "Total time:"
    echo -e "Start: $backup_start"
    echo -e "End:  $backup_end"
    echo -e "\n"
    echo -e "Offline time:"
    echo -e "Start: $oc_offline_start"
    echo -e "End:  $oc_offline_end"
  } >> "$tempdir/oc-backup-$timestamp/oc-message.txt"
  mail -s "ownCloud backup on host '$(hostname -f)' finished successfully" "$mailRecipient" < "$tempdir/oc-backup-$timestamp/oc-message.txt"
  # at the end delete the temporary directory
  rm -r "$tempdir/oc-backup-$timestamp"
else
  echo -e "ownCloud backup on host '$(hostname -f)' failed. The following errors occured:\n" > "$tempdir/oc-backup-$timestamp/oc-message.txt"
  while [ "$num_error" -gt 0 ]; do
    echo -e "${msg_error[$((num_error - 1))]}" >> "$tempdir/oc-backup-$timestamp/oc-message.txt"
    if [ -e "$lockfile" ]; then
      echo -e "${msg_error[$((num_error - 1))]}" >> "$lockfile"
    fi
    num_error=$((num_error - 1))
  done
  if [ -n "$mailRecipient" ]; then
    if mail -s "ownCloud backup on host '$(hostname -f)' failed" "$mailRecipient" < "$tempdir/oc-backup-$timestamp/oc-message.txt"; then
      # delete the temporary directory only if the mail has been sent
      rm -r "$tempdir/oc-backup-$timestamp"
    else
      if [ -e "$tempdir/oc-backup-$timestamp/mysql.cnf" ]; then
        # delete the mysql config to keep the password safe
        rm "$tempdir/oc-backup-$timestamp/mysql.cnf"
      fi
    fi
  fi

  exit 1
fi
exit 0
