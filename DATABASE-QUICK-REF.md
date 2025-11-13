# MyFinance Database Quick Reference

Quick reference guide for database operations in the MyFinance infrastructure.

## 🎯 Quick Commands

### Backup Database

**Linux/macOS:**
```bash
./scripts/database/backup-db.sh
```

**Windows:**
```cmd
scripts\database\backup-db.bat
```

### Restore Database

**Linux/macOS:**
```bash
# List available backups
ls -lh backups/myfinance-*.db

# Restore specific backup
./scripts/database/restore-db.sh backups/myfinance-20251113-143000.db
```

**Windows:**
```cmd
# List available backups
dir backups\myfinance-*.db

# Restore specific backup
scripts\database\restore-db.bat backups\myfinance-20251113-143000.db
```

### Manual Operations

**Copy Database from Container:**
```bash
docker cp myfinance-api-green:/data/myfinance.db ./myfinance-backup.db
```

**Copy Database to Container:**
```bash
docker cp ./myfinance-backup.db myfinance-api-green:/data/myfinance.db
docker restart myfinance-api-green
```

**View Database in Container:**
```bash
docker exec -it myfinance-api-green sqlite3 /data/myfinance.db
```

## 📊 Database Information

| Property | Value |
|----------|-------|
| **Database Type** | SQLite (embedded, file-based) |
| **Database File** | `/data/myfinance.db` |
| **Volume Name** | `shared_api_data` |
| **Connection String** | `Data Source=/data/myfinance.db` |
| **ORM** | Entity Framework Core |
| **Shared By** | Both blue and green environments |

## 🔄 Common Workflows

### Pre-Deployment Backup

```bash
# 1. Create backup
./scripts/database/backup-db.sh  # or .bat on Windows

# 2. Deploy new version (via Jenkins or manually)
# Via Jenkins: Build Backend-Release job with version parameter
# Manual: docker-compose -f docker/blue-green/docker-compose.green.yml up -d

# 3. If issues, restore backup
./scripts/database/restore-db.sh backups/myfinance-YYYYMMDD-HHMMSS.db
```

### Database Rollback

```bash
# 1. List available backups
ls -lh backups/

# 2. Choose backup to restore
./scripts/database/restore-db.sh backups/myfinance-20251113-140000.db

# 3. Verify application works
curl http://localhost/health
```

### Check Database Status

```bash
# Check if database file exists
docker exec myfinance-api-green ls -lh /data/myfinance.db

# View database schema
docker exec -it myfinance-api-green sqlite3 /data/myfinance.db ".schema"

# Check database size
docker exec myfinance-api-green du -h /data/myfinance.db

# View all tables
docker exec myfinance-api-green sqlite3 /data/myfinance.db ".tables"
```

## 🗂️ File Locations

### Host System

| Item | Path |
|------|------|
| **Backups** | `backups/myfinance-*.db` |
| **Safety Backups** | `backups/safety/pre-restore-*.db` |
| **Docker Volume** | `/var/lib/docker/volumes/shared_api_data/_data/` (Linux)<br>`C:\ProgramData\Docker\volumes\shared_api_data\_data\` (Windows) |

### Inside Containers

| Item | Path |
|------|------|
| **Database** | `/data/myfinance.db` |
| **WAL File** | `/data/myfinance.db-wal` |
| **Shared Memory** | `/data/myfinance.db-shm` |

## ⚙️ Configuration Files

### Docker Compose (Blue)
```yaml
# docker/blue-green/docker-compose.blue.yml
volumes:
  shared_api_data:
    driver: local

services:
  myfinance-api:
    volumes:
      - shared_api_data:/data
    environment:
      - ConnectionStrings__DefaultConnection=Data Source=/data/myfinance.db
```

### Docker Compose (Green)
```yaml
# docker/blue-green/docker-compose.green.yml
volumes:
  shared_api_data:
    driver: local

services:
  myfinance-api:
    volumes:
      - shared_api_data:/data
    environment:
      - ConnectionStrings__DefaultConnection=Data Source=/data/myfinance.db
```

## 🚨 Troubleshooting

### No Running Container

**Error:**
```
Error: No running MyFinance API container found
```

**Solution:**
```bash
# Start an environment
docker-compose -f docker/blue-green/docker-compose.green.yml up -d
```

### Database Locked

**Error:**
```
database is locked
```

**Solution:**
- Wait a few seconds and retry
- Check for long-running transactions
- Verify no manual SQLite sessions are open

### Disk Space Full

**Check:**
```bash
df -h
docker system df
```

**Cleanup:**
```bash
# Remove old backups
rm backups/myfinance-*.db

# Clean Docker system
docker system prune -a

# Vacuum database
docker exec myfinance-api-green sqlite3 /data/myfinance.db "VACUUM;"
```

## 📋 Backup Retention

| Type | Retention | Location |
|------|-----------|----------|
| **Automated Backups** | Last 10 | `backups/` |
| **Safety Backups** | Manual cleanup | `backups/safety/` |
| **Deployment Backups** | Before each deploy | `backups/` |

## 🔍 Health Checks

### Database Connectivity

```bash
# Check from container
docker exec myfinance-api-green sqlite3 /data/myfinance.db "SELECT 1;"

# Check API health endpoint
curl http://localhost/api/health
```

### Volume Status

```bash
# List volumes
docker volume ls

# Inspect shared volume
docker volume inspect shared_api_data

# Check volume usage (Linux/macOS)
docker system df -v | grep shared_api_data

# Check volume usage (Windows PowerShell)
docker system df -v | Select-String shared_api_data
```

## 📚 Additional Resources

- **[Database Architecture](docs/database-architecture.md)** - Complete architecture guide
- **[Database Diagrams](docs/database-diagram.md)** - Visual diagrams and flows
- **[Scripts README](scripts/database/README.md)** - Script documentation
- **[Deployment Guide](DEPLOYMENT-GUIDE.md)** - Full deployment procedures
- **[Blue-Green Flow](docs/blue-green-flow.md)** - Deployment flow diagrams

## ⚡ Pro Tips

1. **Always backup before migrations** - Run backup script before any deployment
2. **Test in inactive environment first** - Deploy to inactive, test, then switch
3. **Keep safety backups** - Restore script creates automatic safety backups
4. **Monitor disk space** - SQLite databases grow over time
5. **Use WAL mode** - Already enabled for better concurrency
6. **Schedule backups** - Consider daily automated backups via cron/scheduled tasks
7. **Document migrations** - Keep notes on schema changes for rollback planning

## 🎓 Training Commands

### Beginner

```bash
# View current database
docker exec -it myfinance-api-green sqlite3 /data/myfinance.db

# Inside SQLite prompt:
.tables          # List all tables
.schema          # Show schema
.quit            # Exit
```

### Intermediate

```bash
# Create manual backup with custom name
docker cp myfinance-api-green:/data/myfinance.db backups/before-v1.2.0.db

# Optimize database
docker exec myfinance-api-green sqlite3 /data/myfinance.db "VACUUM; ANALYZE;"
```

### Advanced

```bash
# Database statistics
docker exec myfinance-api-green sqlite3 /data/myfinance.db "
  SELECT 
    name, 
    (SELECT COUNT(*) FROM sqlite_master WHERE type='table') as tables,
    page_count * page_size / 1024 / 1024 as size_mb
  FROM pragma_page_count(), pragma_page_size();
"

# Find largest tables
docker exec myfinance-api-green sqlite3 /data/myfinance.db "
  SELECT name, SUM(pgsize) / 1024 / 1024 as size_mb
  FROM dbstat
  GROUP BY name
  ORDER BY size_mb DESC;
"
```

## 📞 Support

For issues or questions:
1. Check troubleshooting section above
2. Review [database architecture documentation](docs/database-architecture.md)
3. Examine container logs: `docker logs myfinance-api-green`
4. Inspect volume: `docker volume inspect shared_api_data`

---

**Last Updated:** November 2025  
**Version:** 1.0 (Greenfield Implementation)
