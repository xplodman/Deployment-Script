#!/bin/bash
set -e

# Define the list of available actions
list_of_available_actions='List of actions:
1. --upload env [--dry-run|--yes] [path...] (Upload Local Site to env, optionally restricted to one or more relative paths; --dry-run only previews, --yes skips the prompt)
2. --download env [--dry-run|--yes] [path...] (Download env Site to Local, optionally restricted to one or more relative paths; --dry-run only previews, --yes skips the prompt)
3. --ssh env ["command"] (To enter the env server via ssh, or run a one-off command in the site directory)
4. --db env ["SQL query"] (To enter the env database shell, or run a one-off SQL query)
5. --download-db env (Download the env database to Local and remove it from the remote after the download is finished)
6. --import-db env (Import the env database to Local)
7. --upload-db env (Upload Local database to env)
8. --clone-db source_env dest_env (Clone database from one environment to another)
9. --download-mongo-db env (Clone a remote MongoDB database to local MongoDB)'

# Source the credentials file which contains environment-specific variables
. required_scripts/credentials.sh

# Source the script to validate and set environment variables based on input arguments
. required_scripts/validate_and_set_env.sh

# Source the script containing deployment actions such as rsync and database operations
. required_scripts/deployment_actions.sh
