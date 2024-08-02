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

# Function: show_help
# Description:
#   Displays usage instructions and available options.
show_help() {
  echo "Usage: $0 <action> <environment>"
  echo "Available actions: ${list_of_available_actions}"
  echo "Available environments:"
  printf '%s\n' "${environments[@]}"
}

# Main function
main() {
  # Check if both arguments are provided
  if [[ "$1" == "--help" || -z "$1" || -z "$2" ]]; then
    show_help
    exit $ERROR_INVALID_ARGS
  fi

  # Check if the second argument is a valid environment
  if [[ ! -z "$2" ]] && printf '%s\0' "${environments[@]}" | grep -Fxqz -- "$2"; then
    remote_env_name=$2
  else
    log_error "There is no environment with this name ($2)."
    show_help
    exit $ERROR_INVALID_ENV
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
