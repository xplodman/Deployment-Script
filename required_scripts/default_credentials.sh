#!/bin/bash

environments=('production' 'staging') # example ('production' 'staging')

# Local env configuration
local_site_dir=site_directory
local_db_dir=database_directory
local_db_name='local_database_name'
local_db_username='local_database_username'
local_db_password='local_database_password'
special_commands_after_import_db_locally=''
special_commands_after_upload_to_environment=''
db_split_threshold=60

# Local MongoDB configuration (used by --download-mongo-db)
local_mongo_uri='mongodb://localhost:27017' # Remove it if there is no local mongo
local_mongo_db='local_mongo_database_name' # Remove it if there is no local mongo

# Start production environment credentials
## Server credentials
production_port='22' # Default 22
production_user_ip='server_user@server_ip'
production_ssh_password='your_ssh_password_if_exists' # Remove it if there is no password
production_private_key='your_private_key_path' # Remove it if there is no key
production_private_key_password='your_private_key_password_if_exists' # Remove it if there is no password for private key
production_site_dir='server_full_path'

## Database credentials
production_db_name='your_production_db_name'
production_db_host='127.0.0.1' # Default 127.0.0.1
production_db_port='3306' # Default 3306
production_db_username='your_production_db_username'
production_db_password='your_production_db_password'

# Production MongoDB
production_mongo_uri='mongodb://ip:port'
production_mongo_db='mongo-db-name'

# Start staging environment credentials
## Server credentials
staging_port='22' # Default 22
staging_user_ip='server_user@server_ip'
staging_ssh_password='your_ssh_password_if_exists' # Remove it if there is no password
staging_private_key='your_private_key_path' # Remove it if there is no key
staging_private_key_password='your_private_key_password_if_exists' # Remove it if there is no password for private key
staging_site_dir='server_full_path'

## Database credentials
staging_db_name='your_staging_db_name'
staging_db_host='127.0.0.1' # Default 127.0.0.1
staging_db_port='3306' # Default 3306
staging_db_username='your_staging_db_username'
staging_db_password='your_staging_db_password'

# Staging MongoDB
staging_mongo_uri='mongodb://ip:port'
staging_mongo_db='mongo-db-name'
