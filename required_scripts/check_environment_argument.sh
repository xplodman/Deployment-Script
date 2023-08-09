if [[ ! -n "$1" || ! -n "$2" ]]; then
  echo -e "You must add options when you run this file."
  echo -e "${list_of_available_actions}"
  echo -e "List of available environments:"
  echo -e "${environments}"
  exit
fi
if [[ ! -z "$2" ]] && printf '%s\0' "${environments[@]}" | grep -Fxqz -- "$2"; then
  remote_env_name=$2
else
  printf "There is no environment with this name (%s).\n" "$2"
  echo "Available environments is:"
  printf '%s\n' "${environments[@]}"
  exit
fi
