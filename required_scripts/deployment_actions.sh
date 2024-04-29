## Remote environment credentials
if [[ -v ${remote_env_name}_port ]]; then
  x="${remote_env_name}_port"
  env_port="${!x}"
else
  echo "${remote_env_name}_port variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_user_ip ]]; then
  x="${remote_env_name}_user_ip"
  env_user_ip="${!x}"
else
  echo "${remote_env_name}_user_ip variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_site_dir ]]; then
  x="${remote_env_name}_site_dir"
  env_site_dir="${!x}"
else
  echo "${remote_env_name}_site_dir variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_db_name ]]; then
  x="${remote_env_name}_db_name"
  env_db_name="${!x}"
else
  echo "${remote_env_name}_db_name variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_db_host ]]; then
  x="${remote_env_name}_db_host"
  env_db_host="${!x}"
else
  echo "${remote_env_name}_db_host variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_db_port ]]; then
  x="${remote_env_name}_db_port"
  env_db_port="${!x}"
else
  echo "${remote_env_name}_db_port variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_db_username ]]; then
  x="${remote_env_name}_db_username"
  env_db_username="${!x}"
else
  echo "${remote_env_name}_db_username variable not exist"
  exit
fi
if [[ -v ${remote_env_name}_db_password ]]; then
  x="${remote_env_name}_db_password"
  env_db_password="${!x}"
else
  echo "${remote_env_name}_db_password variable not exist"
  exit
fi

if [[ -v ${remote_env_name}_user_ip_port ]]; then
  x="${remote_env_name}_user_ip_port"
  env_user_ip_port="${!x}"
else
  echo "${remote_env_name}_user_ip_port variable not exist"
  exit
fi

if [[ -v ${remote_env_name}_user_ip_site_dir ]]; then
  x="${remote_env_name}_user_ip_site_dir"
  env_user_ip_site_dir="${!x}"
else
  echo "${remote_env_name}_user_ip_site_dir variable not exist"
  exit
fi

if [[ -v ${remote_env_name}_private_key ]]; then
  x="${remote_env_name}_private_key"
  env_private_key_command="-i ${!x}"
else
  env_private_key_command=''
fi

if [[ -v ${remote_env_name}_ssh_password ]]; then
  x="${remote_env_name}_ssh_password"
  env_ssh_password_command="sshpass -p ${!x} "
else
  env_ssh_password_command=''
fi

case $1 in

# Available actions
--upload)
  src="$local_site_dir"
  dest="$env_user_ip_site_dir"
  port="$env_port"
  action="Upload Local Site to $2"
  ;;
--download)
  src="$env_user_ip_site_dir"
  dest="$local_site_dir"
  port="$env_port"
  action="Download $2 Site to Local"
  ;;
--ssh)
  $env_ssh_password_command ssh $env_user_ip_port -t $env_private_key_command "cd "$env_site_dir" && exec bash -l "
  exit
  ;;
--db)
  $env_ssh_password_command ssh $env_user_ip_port -t $env_private_key_command "MYSQL_PWD='"$env_db_password"' mysql -h "$env_db_host" -P "$env_db_port" -u "$env_db_username" "$env_db_name" && exec bash -l "
  exit
  ;;
--download-db)
  src="$env_user_ip_site_dir"
  dest="$local_db_dir"

  echo "Dumping $2 Database"
  $env_ssh_password_command ssh $env_private_key_command $env_user_ip_port -t "cd "$env_site_dir"; MYSQL_PWD='"$env_db_password"' mysqldump -h "$env_db_host" -P "$env_db_port" --no-tablespaces -u "$env_db_username" "$env_db_name" | gzip -9 > "$env_db_name".sql.gz;"

  echo "Downloading $2 Database to Local"
  rsync --rsh="$env_ssh_password_command ssh $env_private_key_command -p"$env_port -iavz --progress --no-times --no-perms --checksum --del "$src"/ "$dest" --include=$env_db_name".sql.gz" --exclude="*" --no-g --no-o

  echo "Removing $2 Database from Remote"
  $env_ssh_password_command ssh $env_user_ip_port -t $env_private_key_command "cd ${env_site_dir}; rm ${env_db_name}.sql.gz"

  exit
  ;;
--import-db)
  DB_EXIST=$(MYSQL_PWD=$local_db_password mysqlshow --user=$local_db_username $local_db_name | grep -v Wildcard | grep -o $local_db_name)

  if [ "$DB_EXIST" == $local_db_name ]; then
    # Database already exists
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

  echo "Restoring ($local_db_name) Database"
  zcat "$local_db_dir"/"$env_db_name".sql.gz | MYSQL_PWD=$local_db_password mysql -u $local_db_username $local_db_name

  if [[ -n $special_commands_after_import_db_locally ]]; then
    echo "Running special commands after import ($local_db_name) Database"
    MYSQL_PWD=$local_db_password mysql -u $local_db_username -e "$special_commands_after_import_db_locally"
  fi
  exit
  ;;
esac

if [ -z "${dest}" ]; then
  echo -e "${list_of_available_actions}"
  exit
fi

# Rsync with dry run option
echo "[Dry Run] $action : $dest"

rsync --rsh="$env_ssh_password_command ssh $env_private_key_command -p"$port -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from=required_scripts/rsync.ignore --stats --no-g --no-o --dry-run

CONT='n'
read -r -p "> Do you want to continue ($action)?[y:N]" CONT

case $CONT in
Y* | y*) ;;
*) exit ;;
esac

# Rsync
rsync --rsh="$env_ssh_password_command ssh $env_private_key_command -p"$port -iavz --no-times --no-perms --checksum --del "$src"/ "$dest" --exclude-from=required_scripts/rsync.ignore --stats --no-g --no-o --progress
