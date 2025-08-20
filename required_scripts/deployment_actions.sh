#!/bin/bash

## Constants
RSYNC_IGNORE_FILE="required_scripts/rsync.ignore"
DB_SPLIT_SIZE_MB=${db_split_threshold:-60}  # Default to 60MB if not set
DB_SPLIT_SIZE=$((DB_SPLIT_SIZE_MB * 1024 * 1024))  # 60MB

# Function to prompt the user for confirmation

# Function to prompt the user for confirmation
prompt_user_confirmation() {
  local action_description="$1"
  local CONT='n'

  read -r -p "> You are about to $action_description. Do you wish to proceed? [y/N]: " CONT

  case $CONT in
    Y* | y*)
      return 0 ;; # Return true (success) if the user confirms
    *)
      echo "Operation cancelled by the user."
      return 1 ;; # Return false (failure) if the user cancels
  esac
}

rsync_action() {
  local action_type="$1"
  local src="$2"
  local dest="$3"
  local port="$4"
  local action_msg="$5"

  # Rsync with dry run option
  log_info "[Dry Run] $action_msg : $dest"
  rsync --rsh="$env_ssh_password ssh $env_private_key -o StrictHostKeyChecking=accept-new -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" --stats --no-g --no-o --dry-run

  # Confirm action with user
  if ! prompt_user_confirmation "$action_msg"; then
    exit 1
  fi

  # Rsync
  rsync --rsh="$env_ssh_password ssh $env_private_key -o StrictHostKeyChecking=accept-new -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" --stats --no-g --no-o --progress

  if [[ -n $special_commands_after_upload_to_environment ]]; then
    log_info "Running special commands after import upload to environment"
    $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; $special_commands_after_upload_to_environment"
  fi
}

execute_ssh_command() {
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key -o StrictHostKeyChecking=accept-new "cd $env_site_dir && exec bash -l"
}

execute_db_command() {
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key -o StrictHostKeyChecking=accept-new "MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name && exec bash -l"
}

download_db_dump() {
  src="$env_user_ip_site_dir"
  dest="$local_db_dir"

  log_info "Dumping $remote_env_name Database"

  if $env_ssh_password ssh $env_user_ip_port -t $env_private_key "command -v mysqldump >/dev/null 2>&1"; then
    # Remote mysqldump available
    $env_ssh_password ssh $env_user_ip_port -t $env_private_key -o StrictHostKeyChecking=accept-new \
      "cd $env_site_dir; MYSQL_PWD='$env_db_password' mysqldump -h $env_db_host -P $env_db_port --no-tablespaces -u $env_db_username $env_db_name | gzip -9 > $env_db_name.sql.gz;"

    log_info "Downloading $remote_env_name Database to Local"
    rsync --rsh="$env_ssh_password ssh $env_private_key -o StrictHostKeyChecking=accept-new -p$env_port" -iavz \
      --no-times --no-perms --checksum --del "$src"/ "$dest" \
      --include=$env_db_name".sql.gz" --exclude="*" --no-g --no-o --progress

    log_info "Removing $remote_env_name Database from Remote"
    $env_ssh_password ssh $env_user_ip_port -t $env_private_key -o StrictHostKeyChecking=accept-new "cd $env_site_dir; rm $env_db_name.sql.gz"
  else
    # Fallback: dump locally
    log_info "mysqldump not found on remote. Dumping locally instead."
    MYSQL_PWD=$env_db_password mysqldump --no-tablespaces --skip-lock-tables \
      -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name \
      | gzip -9 > "$local_db_dir/$env_db_name.sql.gz"
  fi
}

import_db() {
  DB_EXIST=$(MYSQL_PWD=$local_db_password mysqlshow --user=$local_db_username $local_db_name | grep -v Wildcard | grep -o $local_db_name)

  if [ "$DB_EXIST" == "$local_db_name" ]; then
    if ! prompt_user_confirmation "drop and recreate the existing ($local_db_name) database"; then
      exit 1
    fi

    log_info "Deleting ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "DROP DATABASE IF EXISTS ${local_db_name};"
    log_info "Creating ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "CREATE DATABASE ${local_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  else
    log_info "Creating ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "CREATE DATABASE ${local_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  fi

  if ls "$local_db_dir/$env_db_name.sql.gz.part-"* 1> /dev/null 2>&1; then
    log_info "Merging split files for $env_db_name.sql.gz because it is larger than ${DB_SPLIT_SIZE_MB}MB"
    cat "$local_db_dir/$env_db_name.sql.gz.part-"* > "$local_db_dir/$env_db_name.sql.gz"
  fi

  log_info "Restoring ($local_db_name) Database"
  zcat "$local_db_dir"/"$env_db_name".sql.gz | awk 'NR==1 {if (/enable the sandbox mode/) next} {print}' | MYSQL_PWD=$local_db_password mysql -u $local_db_username $local_db_name

  if [[ -n $special_commands_after_import_db_locally ]]; then
    log_info "Running special commands after import ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "$special_commands_after_import_db_locally"
  fi

  if [ $(stat -c%s "$local_db_dir/$env_db_name.sql.gz") -gt $DB_SPLIT_SIZE ]; then
    log_info "Deleting merged file $local_db_dir/$env_db_name.sql.gz after import because it is larger than ${DB_SPLIT_SIZE_MB}MB"
    rm "$local_db_dir/$env_db_name.sql.gz"
  fi
}

upload_db_to_env() {
  local action_msg="upload the local database ($local_db_name) to the remote environment ($remote_env_name). This will replace the existing database on the remote server"

  # Call the confirmation function
  if ! prompt_user_confirmation "$action_msg"; then
    exit 1
  fi

  # Create a dump of the local database
  log_info "Creating a dump of the local database ($local_db_name)"
  MYSQL_PWD=$local_db_password mysqldump -u $local_db_username $local_db_name | gzip -9 > "$local_db_dir/$local_db_name.sql.gz"

  # Upload the database dump to the remote server
  log_info "Uploading the local database dump to the remote server ($remote_env_name)"
  rsync --rsh="$env_ssh_password ssh $env_private_key -p$env_port" -iavz --no-times --no-perms --checksum "$local_db_dir/$local_db_name.sql.gz" "$env_user_ip_site_dir" --no-g --no-o --progress

  # Import the database on the remote server
  log_info "Importing the uploaded database dump on the remote server"
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; gunzip < $local_db_name.sql.gz | MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name"

  # Remove the uploaded dump from the remote server
  log_info "Removing the uploaded database dump from the remote server"
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; rm $local_db_name.sql.gz"

  # Clean up local dump
  rm "$local_db_dir/$local_db_name.sql.gz"
}

main() {
  case $1 in
    --upload)
      rsync_action "upload" "$local_site_dir" "$env_user_ip_site_dir" "$env_port" "Upload Local Site to $2"
      ;;
    --download)
      rsync_action "download" "$env_user_ip_site_dir" "$local_site_dir" "$env_port" "Download $2 Site to Local"
      ;;
    --ssh)
      execute_ssh_command
      ;;
    --db)
      execute_db_command
      ;;
    --download-db)
      download_db_dump
      ;;
    --import-db)
      import_db
      ;;
    --upload-db)
      upload_db_to_env
      ;;
    *)
      echo -e "${list_of_available_actions}"
      exit
      ;;
  esac
}

main "$@"
