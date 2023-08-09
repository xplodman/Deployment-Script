#!/bin/bash
environments=('production' 'staging') # example ('prod' 'staging')

list_of_available_actions='List of actions:
1. --upload env (Upload Local Site to env)
2. --download env (Download env Site to Local)
3. --ssh env (To enter the env server via ssh)
4. --db env (To enter the env database shell)
5. --download-db env (Download the env database to Local and remove it from the remote after the download is finished)
6. --import-db env (Import the env database to Local)'

# Including checking file for second argument is exist in environments array or not
# and declare remote_env_name if exists
. required_scripts/check_environment_argument.sh

# including credentials file
. required_scripts/credentials.sh

# including deployment actions file
. required_scripts/deployment_actions.sh