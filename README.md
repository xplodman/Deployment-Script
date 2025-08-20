# Deployment Script

A comprehensive Bash-based deployment automation tool for web applications that streamlines deployments across multiple environments (production, staging, etc.). This script provides a robust command-line interface for file synchronization, database management, and server access operations.

## 🚀 Features

- **File Synchronization**: Upload/download application files between local and remote environments using rsync
- **Database Management**: Complete database backup, restore, and synchronization capabilities
- **Multi-Environment Support**: Configure and manage multiple deployment environments
- **SSH Integration**: Secure server access and command execution
- **Smart File Handling**: Automatic exclusion of development files and sensitive data
- **User Confirmation**: Interactive prompts for critical operations
- **Comprehensive Logging**: Detailed logging with timestamps for all operations
- **Database Splitting**: Automatic handling of large databases (>60MB) for Git compatibility

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Available Actions](#available-actions)
- [Environment Configuration](#environment-configuration)
- [File Exclusions](#file-exclusions)
- [Database Operations](#database-operations)
- [Security Features](#security-features)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🔧 Prerequisites

Before using this deployment script, ensure you have:

- **SSH Access**: SSH access to your remote environments
- **MySQL Tools**: `mysql` and `mysqldump` commands available locally and remotely
- **rsync**: Available on both local and remote systems
- **Bash**: Version 4.0 or higher
- **Permissions**: Appropriate file and directory permissions on both local and remote systems

## 📦 Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/xplodman/Deployment-Script.git
   cd Deployment-Script
   ```

2. **Set up credentials**:
   ```bash
   cp required_scripts/default_credentials.sh required_scripts/credentials.sh
   ```

3. **Make the script executable**:
   ```bash
   chmod +x deploy_rsync.sh
   ```

4. **Configure your environments** (see [Configuration](#configuration) section)

## ⚙️ Configuration

### 1. Environment Setup

Copy `required_scripts/default_credentials.sh` to `required_scripts/credentials.sh` and configure your environments:

```bash
# Define your environments
environments=('production' 'staging')

# Local environment configuration
local_site_dir=/path/to/your/local/site
local_db_dir=/path/to/your/local/database/dumps
local_db_name='your_local_database'
local_db_username='your_local_db_user'
local_db_password='your_local_db_password'

# Optional: Special commands to run after operations
special_commands_after_import_db_locally=''
special_commands_after_upload_to_environment=''

# Database split threshold (in MB) for Git compatibility
db_split_threshold=60
```

### 2. Environment-Specific Configuration

For each environment (e.g., production, staging), configure:

```bash
# Server credentials
production_port='22'
production_user_ip='username@server_ip'
production_ssh_password='your_ssh_password'  # Remove if using key-based auth
production_private_key='-i /path/to/private_key'  # Remove if using password auth
production_site_dir='/var/www/your_site'

# Database credentials
production_db_name='your_production_db'
production_db_host='127.0.0.1'
production_db_port='3306'
production_db_username='your_db_user'
production_db_password='your_db_password'
```

## 🎯 Usage

### Basic Syntax
```bash
./deploy_rsync.sh <action> <environment>
```

### Examples
```bash
# Upload local site to production
./deploy_rsync.sh --upload production

# Download staging site to local
./deploy_rsync.sh --download staging

# SSH into production server
./deploy_rsync.sh --ssh production

# Access production database shell
./deploy_rsync.sh --db production

# Download production database to local
./deploy_rsync.sh --download-db production

# Import staging database to local
./deploy_rsync.sh --import-db staging

# Upload local database to staging
./deploy_rsync.sh --upload-db staging
```

## 🔄 Available Actions

### 1. File Synchronization

#### `--upload env`
- **Purpose**: Upload local application files to remote environment
- **Process**: 
  - Performs dry-run first to show what will be uploaded
  - Prompts for user confirmation
  - Executes rsync with optimized flags
  - Runs optional post-upload commands
- **Flags**: `-iavz --no-times --no-perms --checksum --del`
- **Exclusions**: Uses `rsync.ignore` file for file filtering

#### `--download env`
- **Purpose**: Download remote application files to local machine
- **Process**: Same as upload but in reverse direction
- **Use Case**: Backup remote site, sync changes from production

### 2. Server Access

#### `--ssh env`
- **Purpose**: SSH into remote environment server
- **Features**: 
  - Automatically navigates to site directory
  - Provides interactive bash shell
  - Uses configured SSH credentials

#### `--db env`
- **Purpose**: Access remote database shell
- **Features**:
  - Connects directly to MySQL/MariaDB
  - Uses environment-specific database credentials
  - Provides interactive database shell

### 3. Database Operations

#### `--download-db env`
- **Purpose**: Download remote database to local machine
- **Process**:
  - Creates compressed database dump on remote server
  - Downloads dump file to local machine
  - Removes temporary dump from remote server
  - Handles large databases with automatic splitting
- **Output**: `{db_name}.sql.gz` in local database directory

#### `--import-db env`
- **Purpose**: Import downloaded database into local database
- **Process**:
  - Checks for existing local database
  - Prompts for confirmation before dropping existing DB
  - Creates new database with UTF8MB4 charset
  - Merges split files if database was large
  - Imports data with sandbox mode handling
  - Runs optional post-import commands
  - Cleans up large merged files

#### `--upload-db env`
- **Purpose**: Upload local database to remote environment
- **Process**:
  - Creates local database dump
  - Uploads dump to remote server
  - Imports database on remote server
  - Cleans up temporary files
- **Warning**: **This will replace the existing remote database!**

## 📁 File Exclusions

The script automatically excludes development and sensitive files using `rsync.ignore`:

```
/storage/*.key          # Encryption keys
/storage/framework      # Framework cache
/public/storage         # Public storage
/node_modules           # Node.js dependencies
/storage/logs           # Application logs
.env                    # Environment variables
/vendor                 # PHP dependencies
/.git                   # Git repository
bootstrap/cache         # Bootstrap cache
.htaccess              # Apache configuration
error_log              # Error logs
```

## 🗄️ Database Operations

### Database Splitting
- **Threshold**: Configurable (default: 60MB)
- **Purpose**: Split large databases for Git repository compatibility
- **Process**: Automatic splitting during download, merging during import

### Supported Database Types
- MySQL 5.7+
- MariaDB 10.2+
- Compatible with most MySQL-compatible databases

### Security Features
- **No Tablespaces**: Prevents tablespace-related issues
- **Skip Lock Tables**: Avoids locking issues during backup
- **Sandbox Mode Handling**: Automatically handles sandbox mode in dumps

## 🔒 Security Features

- **SSH Key Support**: Primary authentication method
- **Password Fallback**: SSH password authentication when needed
- **Strict Host Key Checking**: Prevents man-in-the-middle attacks
- **Credential Isolation**: Separate configuration file for sensitive data
- **User Confirmation**: Prompts for destructive operations

## 🚨 Safety Features

- **Dry Run**: File operations show what will happen before execution
- **User Confirmation**: Critical operations require explicit confirmation
- **Error Handling**: Comprehensive error checking and logging
- **Rollback Support**: Database operations can be reversed
- **Logging**: All operations are logged with timestamps

## 🔍 Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify SSH credentials in `credentials.sh`
   - Check SSH key permissions (`chmod 600`)
   - Ensure SSH service is running on remote server

2. **Database Connection Failed**
   - Verify database credentials
   - Check if database server is accessible
   - Ensure MySQL/MariaDB service is running

3. **Permission Denied**
   - Check file/directory permissions
   - Verify user has appropriate access rights
   - Check SSH key permissions

4. **rsync Errors**
   - Verify rsync is installed on both systems
   - Check network connectivity
   - Ensure sufficient disk space

### Debug Mode
Enable verbose logging by modifying the script or checking the console output for detailed information.

## 📝 Logging

The script provides comprehensive logging:
- **Timestamps**: All operations include timestamps
- **Error Logging**: Detailed error messages with context
- **Info Logging**: Progress information for all operations
- **User Actions**: Confirmation prompts and user decisions

## 🛠️ Advanced Configuration

### Custom rsync Options
Modify `deployment_actions.sh` to customize rsync behavior:
- Change compression levels
- Modify exclusion patterns
- Adjust bandwidth limits
- Customize file permissions

### Post-Operation Commands
Configure custom commands to run after specific operations:
```bash
special_commands_after_import_db_locally='UPDATE users SET email = "test@example.com";'
special_commands_after_upload_to_environment='php artisan cache:clear && php artisan config:cache'
```

### Database Split Threshold
Adjust the database splitting threshold based on your Git repository limits:
```bash
db_split_threshold=100  # 100MB threshold
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Guidelines
- Follow Bash best practices
- Add comprehensive error handling
- Include logging for all operations
- Test with multiple environments
- Update documentation for new features

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🆘 Support

For support and questions:
- Open an issue on GitHub
- Check the troubleshooting section
- Review the configuration examples
- Ensure all prerequisites are met

---

**Note**: This script is designed for development and staging environments. Use in production with caution and always test thoroughly before deployment.
