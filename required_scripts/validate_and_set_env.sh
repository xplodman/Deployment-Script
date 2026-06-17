#!/bin/bash

# Constants
ERROR_INVALID_ARGS=1
ERROR_INVALID_ENV=2
ERROR_REQUIRED_VAR=3

# Function: log_error
# Logs an error message with a timestamp to the console and optionally to a log file.
log_error() {
  local message="$1"
  echo "$(date +'%Y-%m-%d %H:%M:%S') ERROR: $message"
}

# Function: log_info
# Logs an info message with a timestamp to the console and optionally to a log file.
log_info() {
  local message="$1"
  echo "$(date +'%Y-%m-%d %H:%M:%S') INFO: $message"
}

# Function: check_and_set_env_var
# Description:
#   This function checks if a specified environment variable is set and optionally formats its value.
#   It handles cases where the variable is required or optional and ensures required variables are not empty.
# Parameters:
#   1. var_name (string): The base name of the environment variable to check.
#   2. is_required (string): A flag ("true" or "false") indicating if the variable is required.
#   3. special_format (string): An optional format string to modify the variable's value. Use "XX" as a placeholder for the value.
# Environment Variables:
#   remote_env_name (string): A prefix used to form the full environment variable name.
check_and_set_env_var() {
  local var_name="$1"
  local is_required="$2"
  local special_format="$3"
  local env_var="${remote_env_name}_$var_name"
  local var_value=""

  # Check if the environment variable is set and not null
  if [ ! -z "${!env_var+x}" ]; then
    var_value="${!env_var}"
    if [[ -n "$special_format" ]]; then
      eval "env_$var_name=\"${special_format//XX/${var_value}}\""
    else
      eval "env_$var_name=\${var_value}"
    fi
  fi

  # Check if the variable is required, must not be empty, and set value accordingly
  if [[ "$is_required" == "true" && ( -z "${!env_var+x}" || -z "${!env_var}" ) ]]; then
    log_error "${env_var} variable is required but not set or is empty"
    exit $ERROR_REQUIRED_VAR
  elif [[ "$is_required" != "true" && ( -z "${!env_var+x}" || -z "${!env_var}" ) ]]; then
    eval "env_$var_name=''"
  fi
}

# Function: combining_credentials_variables
# Combines user, IP, port, and site directory for a given remote environment.
combining_credentials_variables(){
    # Create <env_name>_user_ip_port variable
    eval "${remote_env_name}_user_ip_port=\$${remote_env_name}_user_ip' -p '\$${remote_env_name}_port"

    # Create <env_name>_user_ip_site_dir variable
    eval "${remote_env_name}_user_ip_site_dir=\$${remote_env_name}_user_ip':'\$${remote_env_name}_site_dir"
}

# Function: validate_environment_name
# Description:
#   Validates that the given name exists in the environments array.
validate_environment_name() {
  local env_name="$1"
  if printf '%s\0' "${environments[@]}" | grep -Fxqz -- "$env_name"; then
    return 0
  fi
  log_error "There is no environment with this name ($env_name)."
  return 1
}

# Function: set_remote_environment
# Description:
#   Loads credentials for a named environment into env_* variables.
set_remote_environment() {
  local env_name="$1"

  if ! validate_environment_name "$env_name"; then
    show_help
    exit $ERROR_INVALID_ENV
  fi

  remote_env_name=$env_name
  combining_credentials_variables

  check_and_set_env_var "port" true
  check_and_set_env_var "user_ip" true
  check_and_set_env_var "site_dir" true
  check_and_set_env_var "db_access_method" false
  check_and_set_env_var "db_name" true
  check_and_set_env_var "db_host" true
  check_and_set_env_var "db_port" true
  check_and_set_env_var "db_username" true
  check_and_set_env_var "db_password" true
  check_and_set_env_var "user_ip_port" true
  check_and_set_env_var "user_ip_site_dir" true

  check_and_set_env_var "private_key" false "-i XX"
  check_and_set_env_var "private_key_password" false "sshpass -P passphrase -p XX"
  check_and_set_env_var "ssh_password" false "sshpass -p XX"

  check_and_set_env_var "mongo_uri" false
  check_and_set_env_var "mongo_db" false
}

# Function: show_help
# Description:
#   Displays usage instructions and available options.
show_help() {
  log_info 'Usage instructions and available options.'
  echo "Usage: $0 <action> <environment>"
  echo "       $0 --clone-db <source_environment> <destination_environment>"
  echo "Available actions: ${list_of_available_actions}"
  echo "Available environments:"
  printf '%s\n' "${environments[@]}"
}

# Main function
main() {
  if [[ "$1" == "--help" || -z "$1" ]]; then
    show_help
    exit $ERROR_INVALID_ARGS
  fi

  if [[ "$1" == "--clone-db" ]]; then
    if [[ -z "$2" || -z "$3" ]]; then
      log_error "--clone-db requires source and destination environments."
      show_help
      exit $ERROR_INVALID_ARGS
    fi
    for env_name in "$2" "$3"; do
      if ! validate_environment_name "$env_name"; then
        show_help
        exit $ERROR_INVALID_ENV
      fi
    done
    return 0
  fi

  if [[ -z "$2" ]]; then
    show_help
    exit $ERROR_INVALID_ARGS
  fi

  set_remote_environment "$2"
}

# Run the main function with provided arguments
main "$@"
