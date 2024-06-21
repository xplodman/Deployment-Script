#!/bin/bash

## Constants
RSYNC_IGNORE_FILE="required_scripts/rsync.ignore"
DB_SPLIT_SIZE=$((60 * 1024 * 1024))  # 60MB

rsync_action() {
  local action_type="$1"
  local src="$2"
  local dest="$3"
  local port="$4"
  local action_msg="$5"

  # Rsync with dry run option
  echo "[Dry Run] $action_msg : $dest"
  rsync --rsh="$env_ssh_password ssh $env_private_key -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" --stats --no-g --no-o --dry-run

  CONT='n'
  read -r -p "> Do you want to continue ($action_msg)?[y:N]" CONT

  case $CONT in
    Y* | y*) ;;
    *) exit ;;
  esac

  # Rsync
  rsync --rsh="$env_ssh_password ssh $env_private_key -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" --stats --no-g --no-o --progress
}

execute_ssh_command() {
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir && exec bash -l"
}

execute_db_command() {
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name && exec bash -l"
}

download_db_dump() {
  src="$env_user_ip_site_dir"
  dest="$local_db_dir"

  echo "Dumping $remote_env_name Database"
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; MYSQL_PWD='$env_db_password' mysqldump -h $env_db_host -P $env_db_port --no-tablespaces -u $env_db_username $env_db_name | gzip -9 > $env_db_name.sql.gz;"

  echo "Downloading $remote_env_name Database to Local"
  rsync --rsh="$env_ssh_password ssh $env_private_key -p$env_port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --include=$env_db_name".sql.gz" --exclude="*" --no-g --no-o --progress

  echo "Removing $remote_env_name Database from Remote"
  $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; rm $env_db_name.sql.gz"

  # Split the file if it's larger than 60MB
  if [ $(stat -c%s "$local_db_dir/$env_db_name.sql.gz") -gt $DB_SPLIT_SIZE ]; then
    echo "Splitting $env_db_name.sql.gz because it is larger than 60MB"
    split -b 60m "$local_db_dir/$env_db_name.sql.gz" "$local_db_dir/$env_db_name.sql.gz.part-"
    rm "$local_db_dir/$env_db_name.sql.gz"
  fi
}

import_db() {
  DB_EXIST=$(MYSQL_PWD=$local_db_password mysqlshow --user=$local_db_username $local_db_name | grep -v Wildcard | grep -o $local_db_name)

  if [ "$DB_EXIST" == $local_db_name ]; then
    read -r -p "(${local_db_name}) database already exists - are you sure to drop (${local_db_name}) database? (y/n)?" choice
    case "$choice" in
      Y* | y*)
        echo "Deleting ($local_db_name) Database"
        MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "DROP DATABASE IF EXISTS ${local_db_name};"
        echo "Creating ($local_db_name) Database"
        MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "CREATE DATABASE ${local_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        ;;
      *) exit ;;
    esac
  else
    echo "Creating ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "CREATE DATABASE ${local_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  fi

  if ls "$local_db_dir/$env_db_name.sql.gz.part-"* 1> /dev/null 2>&1; then
    echo "Merging split files for $env_db_name.sql.gz because it is larger than 60MB"
    cat "$local_db_dir/$env_db_name.sql.gz.part-"* > "$local_db_dir/$env_db_name.sql.gz"
  fi

  echo "Restoring ($local_db_name) Database"
  zcat "$local_db_dir"/"$env_db_name".sql.gz | MYSQL_PWD=$local_db_password mysql -u $local_db_username $local_db_name

  if [[ -n $special_commands_after_import_db_locally ]]; then
    echo "Running special commands after import ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "$special_commands_after_import_db_locally"
  fi

  if [ $(stat -c%s "$local_db_dir/$env_db_name.sql.gz") -gt $DB_SPLIT_SIZE ]; then
    echo "Deleting merged file $local_db_dir/$env_db_name.sql.gz after import because it is larger than 60MB"
    rm "$local_db_dir/$env_db_name.sql.gz"
  fi
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
    *)
      echo -e "${list_of_available_actions}"
      exit
      ;;
  esac
}

main "$@"
