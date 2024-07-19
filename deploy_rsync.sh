#!/bin/bash

# Define the list of available actions
list_of_available_actions='List of actions:
1. --upload env (Upload Local Site to env)
2. --download env (Download env Site to Local)
3. --ssh env (To enter the env server via ssh)
4. --db env (To enter the env database shell)
5. --download-db env (Download the env database to Local and remove it from the remote after the download is finished)
6. --import-db env (Import the env database to Local)'

# Source the credentials file which contains environment-specific variables
. credentials.sh

# Source the script to validate and set environment variables based on input arguments
. validate_and_set_env.sh

# Source the script containing deployment actions such as rsync and database operations
. deployment_actions.sh
