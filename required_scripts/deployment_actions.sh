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

# Function: build_scoped_filters
# Description:
#   Populates the global SCOPED_FILTERS array with rsync --include/--exclude
#   rules that restrict a sync to one or more relative paths (file or
#   directory), while still letting rules that come before it (e.g.
#   --exclude-from) win. Ancestor directories must be explicitly included or
#   rsync won't descend into them to reach the target paths.
build_scoped_filters() {
  SCOPED_FILTERS=()
  local rel_path

  for rel_path in "$@"; do
    rel_path="${rel_path#/}"
    rel_path="${rel_path%/}"
    [[ -z "$rel_path" ]] && continue

    local accum=""
    local part
    local IFS='/'
    local parts=($rel_path)
    unset IFS
    for part in "${parts[@]}"; do
      accum="${accum:+$accum/}$part"
      SCOPED_FILTERS+=(--include="$accum/")
    done
    SCOPED_FILTERS+=(--include="$rel_path")
    SCOPED_FILTERS+=(--include="$rel_path/***")
  done
  SCOPED_FILTERS+=(--exclude=*)
}

rsync_action() {
  local action_type="$1"
  local src="$2"
  local dest="$3"
  local port="$4"
  local action_msg="$5"
  shift 5
  local rel_paths=("$@")

  SCOPED_FILTERS=()
  if [[ ${#rel_paths[@]} -gt 0 ]]; then
    build_scoped_filters "${rel_paths[@]}"
    local joined_paths
    joined_paths=$(IFS=', '; echo "${rel_paths[*]}")
    action_msg="$action_msg (path(s): $joined_paths)"
  fi

  # Rsync with dry run option
  log_info "[Dry Run] $action_msg : $dest"
  rsync --rsh="$env_private_key_password $env_ssh_password ssh $env_private_key -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" "${SCOPED_FILTERS[@]}" --stats --no-g --no-o --dry-run

  # Confirm action with user
  if ! prompt_user_confirmation "$action_msg"; then
    exit 1
  fi

  # Rsync
  rsync --rsh="$env_private_key_password $env_ssh_password ssh $env_private_key -p$port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from="$RSYNC_IGNORE_FILE" "${SCOPED_FILTERS[@]}" --stats --no-g --no-o --progress

  if [[ -n $special_commands_after_upload_to_environment ]]; then
    log_info "Running special commands after import upload to environment"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; $special_commands_after_upload_to_environment"
  fi
}

execute_ssh_command() {
  $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir && exec bash -l"
}

execute_db_command() {
  if [[ "${env_db_access_method}" == 'direct' ]]; then
    log_info "Connecting to $remote_env_name database directly from your machine"
    MYSQL_PWD="$env_db_password" mysql -h "$env_db_host" -P "$env_db_port" -u "$env_db_username" "$env_db_name"
  else
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name && exec bash -l"
  fi
}

download_db_dump() {
  dest="$local_db_dir"
  local start_time=$SECONDS

  log_info "Starting database download for $remote_env_name ($env_db_name)"

  # Use --single-transaction to avoid LOCK TABLES (no LOCK TABLES privilege needed; consistent dump for InnoDB)
  local mysqldump_opts="-h $env_db_host -P $env_db_port --no-tablespaces --single-transaction -u $env_db_username $env_db_name"
  if [[ "${env_db_access_method}" == 'direct' ]]; then
    log_info "Dumping $remote_env_name Database directly from your machine"
    MYSQL_PWD="$env_db_password" mysqldump $mysqldump_opts | gzip -9 > "$local_db_dir/$env_db_name.sql.gz"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      log_error "mysqldump failed while dumping $remote_env_name Database ($env_db_name)"
      exit 1
    fi
    log_info "Dump complete, saved to $local_db_dir/$env_db_name.sql.gz"
  else
    src="$env_user_ip_site_dir"
    log_info "Dumping $remote_env_name Database (via environment server)"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; MYSQL_PWD='$env_db_password' mysqldump $mysqldump_opts | gzip -9 > $env_db_name.sql.gz;"

    log_info "Downloading $remote_env_name Database to Local"
    rsync --rsh="$env_private_key_password $env_ssh_password ssh $env_private_key -p$env_port" -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --include=$env_db_name".sql.gz" --exclude="*" --no-g --no-o --progress

    log_info "Removing $remote_env_name Database from Remote"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; rm $env_db_name.sql.gz"
  fi

  # Split the file if it's larger than the specified size
  if [ -f "$local_db_dir/$env_db_name.sql.gz" ] && [ $(stat -c%s "$local_db_dir/$env_db_name.sql.gz") -gt $DB_SPLIT_SIZE ]; then
    log_info "Splitting $env_db_name.sql.gz because it is larger than ${DB_SPLIT_SIZE_MB}MB"
    split -b "${DB_SPLIT_SIZE_MB}m" "$local_db_dir/$env_db_name.sql.gz" "$local_db_dir/$env_db_name.sql.gz.part-"
    rm "$local_db_dir/$env_db_name.sql.gz"
  fi

  local elapsed=$((SECONDS - start_time))
  local total_size
  total_size=$(du -ch "$local_db_dir"/"$env_db_name".sql.gz* 2>/dev/null | tail -1 | cut -f1)
  log_info "Finished downloading $remote_env_name Database ($env_db_name) in ${elapsed}s (${total_size:-unknown size})"
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

merge_db_dump_if_split() {
  local dump_db_name="$1"

  if ls "$local_db_dir/$dump_db_name.sql.gz.part-"* 1> /dev/null 2>&1; then
    log_info "Merging split files for $dump_db_name.sql.gz because it is larger than ${DB_SPLIT_SIZE_MB}MB"
    cat "$local_db_dir/$dump_db_name.sql.gz.part-"* > "$local_db_dir/$dump_db_name.sql.gz"
  fi
}

cleanup_db_dump() {
  local dump_db_name="$1"

  rm -f "$local_db_dir/$dump_db_name.sql.gz"
  rm -f "$local_db_dir/$dump_db_name.sql.gz.part-"*
}

import_db_dump_to_env() {
  local dump_db_name="$1"

  merge_db_dump_if_split "$dump_db_name"

  if [[ ! -f "$local_db_dir/$dump_db_name.sql.gz" ]]; then
    log_error "Database dump file not found: $local_db_dir/$dump_db_name.sql.gz"
    exit 1
  fi

  if [[ "${env_db_access_method}" == 'direct' ]]; then
    log_info "Importing database dump directly from your machine into $remote_env_name ($env_db_name)"
    zcat "$local_db_dir/$dump_db_name.sql.gz" | awk 'NR==1 {if (/enable the sandbox mode/) next} {print}' | MYSQL_PWD="$env_db_password" mysql -h "$env_db_host" -P "$env_db_port" -u "$env_db_username" "$env_db_name"
  else
    log_info "Uploading database dump ($dump_db_name) to $remote_env_name"
    rsync --rsh="$env_private_key_password $env_ssh_password ssh $env_private_key -p$env_port" -iavz --no-times --no-perms --checksum "$local_db_dir/$dump_db_name.sql.gz" "$env_user_ip_site_dir" --no-g --no-o --progress

    log_info "Importing database dump into $remote_env_name ($env_db_name)"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; gunzip < $dump_db_name.sql.gz | awk 'NR==1 {if (/enable the sandbox mode/) next} {print}' | MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name"

    log_info "Removing the uploaded database dump from $remote_env_name"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; rm $dump_db_name.sql.gz"
  fi

  if [[ -n $special_commands_after_upload_to_environment ]]; then
    log_info "Running special commands after database import to $remote_env_name"
    $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; $special_commands_after_upload_to_environment"
  fi

  cleanup_db_dump "$dump_db_name"
}

clone_db_env_to_env() {
  local source_env="$1"
  local dest_env="$2"
  local source_db_name=""

  if [[ "$source_env" == "$dest_env" ]]; then
    log_error "Source and destination environments must be different."
    exit 1
  fi

  local action_msg="clone the database from $source_env to $dest_env. This will replace the existing database on $dest_env"
  if ! prompt_user_confirmation "$action_msg"; then
    exit 1
  fi

  log_info "Step 1/2: Dumping database from $source_env"
  set_remote_environment "$source_env"
  source_db_name="$env_db_name"
  download_db_dump

  log_info "Step 2/2: Importing database into $dest_env"
  set_remote_environment "$dest_env"
  import_db_dump_to_env "$source_db_name"

  log_info "Database cloned from $source_env to $dest_env successfully"
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
  rsync --rsh="$env_private_key_password $env_ssh_password ssh $env_private_key -p$env_port" -iavz --no-times --no-perms --checksum "$local_db_dir/$local_db_name.sql.gz" "$env_user_ip_site_dir" --no-g --no-o --progress

  # Import the database on the remote server
  log_info "Importing the uploaded database dump on the remote server"
  $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; gunzip < $local_db_name.sql.gz | MYSQL_PWD='$env_db_password' mysql -h $env_db_host -P $env_db_port -u $env_db_username $env_db_name"

  # Remove the uploaded dump from the remote server
  log_info "Removing the uploaded database dump from the remote server"
  $env_private_key_password $env_ssh_password ssh $env_user_ip_port -t $env_private_key "cd $env_site_dir; rm $local_db_name.sql.gz"

  # Clean up local dump
  rm "$local_db_dir/$local_db_name.sql.gz"
}

download_mongo_db() {
  local source_uri="${env_mongo_uri}"
  local source_db="${env_mongo_db}"
  local target_uri="${local_mongo_uri}"
  local target_db="${local_mongo_db}"

  if [[ -z "$source_uri" || -z "$source_db" || -z "$target_uri" || -z "$target_db" ]]; then
    log_error "MongoDB variables are missing. Ensure <env>_mongo_uri, <env>_mongo_db, local_mongo_uri, and local_mongo_db are set."
    exit 1
  fi

  local action_msg="drop local MongoDB database ($target_db) and clone from ($source_db) at ($source_uri)"
  if ! prompt_user_confirmation "$action_msg"; then
    exit 1
  fi

  log_info "Dropping local database ($target_db) and cloning from ($source_uri/$source_db) to ($target_uri/$target_db)"
  /bin/bash -c "mongosh ${target_uri}/${target_db} --eval 'db.dropDatabase()' && mongodump --uri='${source_uri}' --db='${source_db}' --archive --gzip | mongorestore --uri='${target_uri}' --archive --gzip --nsFrom='${source_db}.*' --nsTo='${target_db}.*'"
}

main() {
  case $1 in
    --upload)
      rsync_action "upload" "$local_site_dir" "$env_user_ip_site_dir" "$env_port" "Upload Local Site to $2" "${@:3}"
      ;;
    --download)
      rsync_action "download" "$env_user_ip_site_dir" "$local_site_dir" "$env_port" "Download $2 Site to Local" "${@:3}"
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
    --clone-db)
      clone_db_env_to_env "$2" "$3"
      ;;
    --download-mongo-db)
      download_mongo_db
      ;;
    *)
      echo -e "${list_of_available_actions}"
      exit
      ;;
  esac
}

main "$@"
