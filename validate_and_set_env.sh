#!/bin/bash

# Function to check and set environment variables
check_and_set_env_var() {
  local var_name="$1"
  local is_required="$2"
  local special_format="$3"
  local env_var="${remote_env_name}_$var_name"

  if [[ -v ${env_var} ]]; then
    x="${env_var}"
    if [[ -n "$special_format" ]]; then
      eval "env_$var_name=\"${special_format//XX/\${!x}}\""
    else
      eval "env_$var_name=\${!x}"
    fi
  elif [[ "$is_required" == "true" ]]; then
    echo "Error: ${env_var} variable not exist"
    exit 1
  else
    eval "env_$var_name=''"
  fi
}

main() {
  # Check if both arguments are provided
  if [[ ! -n "$1" || ! -n "$2" ]]; then
    echo -e "You must add options when you run this file."
    echo -e "${list_of_available_actions}"
    echo -e "List of available environments:"
    echo -e "${environments}"
    exit 1
  fi

  # Check if the second argument is a valid environment
  if [[ ! -z "$2" ]] && printf '%s\0' "${environments[@]}" | grep -Fxqz -- "$2"; then
    remote_env_name=$2
  else
    printf "There is no environment with this name (%s).\n" "$2"
    echo "Available environments are:"
    printf '%s\n' "${environments[@]}"
    exit 1
  fi

  # Check and set required environment variables
  check_and_set_env_var "port" true
  check_and_set_env_var "user_ip" true
  check_and_set_env_var "site_dir" true
  check_and_set_env_var "db_name" true
  check_and_set_env_var "db_host" true
  check_and_set_env_var "db_port" true
  check_and_set_env_var "db_username" true
  check_and_set_env_var "db_password" true
  check_and_set_env_var "user_ip_port" true
  check_and_set_env_var "user_ip_site_dir" true

  # Check and set optional environment variables with special formats
  check_and_set_env_var "private_key" false "-i XX"
  check_and_set_env_var "ssh_password" false "sshpass -p XX"
}

# Run the main function with provided arguments
main "$@"
