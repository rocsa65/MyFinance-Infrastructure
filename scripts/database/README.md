# Database Management Scripts

This directory contains automation scripts for managing the MyFinance SQLite database in both blue and green deployment environments.

## 📋 Overview

Both blue and green environments share the same database file (`myfinance.db`) through a shared Docker volume (`shared_api_data`). These scripts help you backup and restore the database safely.

## 🛠️ Available Scripts

### Backup Scripts

#### Linux/macOS: `backup-db.sh`
Creates a timestamped backup of the shared database.

```bash
./scripts/database/backup-db.sh
```

**Features:**
- Creates timestamped backup in `backups/` directory
- Verifies backup integrity
- Automatically cleans up old backups (keeps last 10)
- Works with either blue or green running container

#### Windows: `backup-db.bat`
Windows version of the backup script.

```cmd
scripts\database\backup-db.bat
```

**Features:**
- Same functionality as Linux version
- Windows-compatible commands and paths

### Restore Scripts

#### Linux/macOS: `restore-db.sh`
Restores the database from a backup file.

```bash
./scripts/database/restore-db.sh <backup-file>
```

**Features:**
- Creates safety backup before restore
- Restores to all running environments
- Requires manual confirmation
- Automatically restarts containers

**Example:**
```bash
./scripts/database/restore-db.sh backups/myfinance-20240115-143000.db
```

#### Windows: `restore-db.bat`
Windows version of the restore script.

```cmd
scripts\database\restore-db.bat <backup-file>
```

**Example:**
```cmd
scripts\database\restore-db.bat backups\myfinance-20240115-143000.db
```

### Migration Script

#### `migrate.sh`
Runs Entity Framework Core migrations (deprecated - migrations now run automatically).

```bash
./scripts/database/migrate.sh <environment>
```

## 📁 Backup Structure

```
backups/
├── myfinance-20240115-143000.db
├── myfinance-20240115-150000.db
├── myfinance-20240115-160000.db
└── safety/
    └── pre-restore-20240115-170000.db
```

- **Regular backups**: Timestamped database backups
- **Safety backups**: Created automatically before restore operations

## 🔄 Common Workflows

### Before Major Deployment
```bash
# Create backup
./scripts/database/backup-db.sh

# Proceed with deployment
./scripts/deployment/deploy-backend.sh v1.2.0
```

### Rollback Database
```bash
# List available backups
ls -lh backups/myfinance-*.db

# Restore specific backup
./scripts/database/restore-db.sh backups/myfinance-20240115-143000.db
```

### Manual Database Operations
```bash
# Copy database from container
docker cp myfinance-api-green:/data/myfinance.db ./local-copy.db

# Copy database to container
docker cp ./local-copy.db myfinance-api-green:/data/myfinance.db

# Restart container to reload
docker restart myfinance-api-green
```

## ⚠️ Important Notes

1. **Shared Database**: Both blue and green environments use the same database file
2. **Backup Before Deploy**: Always create a backup before major deployments
3. **Safety First**: Restore script creates automatic safety backup
4. **Container Restart**: Containers are automatically restarted after restore
5. **Cleanup**: Old backups are automatically cleaned up (last 10 kept)

## 🔍 Troubleshooting

### No Running Container
```
Error: No running MyFinance API container found
```
**Solution**: Start at least one environment (blue or green)

### Backup File Not Found
```
Error: Backup file not found: <file>
```
**Solution**: Check backup file path and name

### Permission Issues (Linux/macOS)
```bash
# Make scripts executable
chmod +x scripts/database/*.sh
```

## 📚 Additional Resources

- [Database Architecture](../../docs/database-architecture.md) - Complete database architecture guide
- [Quick Reference](../../DATABASE-QUICK-REF.md) - Quick command reference
- [Blue-Green Flow](../../docs/blue-green-flow.md) - Deployment flow diagrams

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the database architecture documentation
3. Examine container logs: `docker logs myfinance-api-green`
