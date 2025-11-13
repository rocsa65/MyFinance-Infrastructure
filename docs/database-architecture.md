# MyFinance Database Architecture

## 🏗️ Overview

This document describes the database architecture for MyFinance using a **shared database approach** for blue-green deployments. This is a greenfield implementation designed for zero-downtime deployments with data persistence.

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Host                              │
│                                                               │
│  ┌────────────────────────┐  ┌────────────────────────┐    │
│  │  Blue Environment      │  │  Green Environment     │    │
│  │  (myfinance-api-blue)  │  │  (myfinance-api-green) │    │
│  │                        │  │                        │    │
│  │  Port: 5001            │  │  Port: 5002            │    │
│  │                        │  │                        │    │
│  │  ┌──────────────────┐  │  │  ┌──────────────────┐  │    │
│  │  │   API Container  │  │  │  │   API Container  │  │    │
│  │  │                  │  │  │  │                  │  │    │
│  │  │  /data/          │◄─┼──┼─►│  /data/          │  │    │
│  │  │   myfinance.db   │  │  │  │   myfinance.db   │  │    │
│  │  └────────┬─────────┘  │  │  └────────┬─────────┘  │    │
│  │           │            │  │           │            │    │
│  └───────────┼────────────┘  └───────────┼────────────┘    │
│              │                           │                  │
│              └───────────┬───────────────┘                  │
│                          │                                  │
│                          ▼                                  │
│              ┌───────────────────────┐                      │
│              │  Shared Docker Volume │                      │
│              │   shared_api_data     │                      │
│              │                       │                      │
│              │   myfinance.db        │                      │
│              │   (SQLite Database)   │                      │
│              └───────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘

External Access:
  └─► Nginx Reverse Proxy (Port 80)
       └─► Routes to Active Environment (Blue or Green)
```

## 🗄️ Database Technology

- **Type**: SQLite (embedded, file-based)
- **File**: `myfinance.db`
- **Location**: `/data/myfinance.db` (inside containers)
- **ORM**: Entity Framework Core
- **Migrations**: Automated through EF Core

## 🔄 Shared Database Design

### Why Shared Database?

In a traditional blue-green deployment with separate databases, switching between environments would lose all data. The shared database approach ensures:

1. **Data Persistence**: Data remains intact across all deployments
2. **Zero Downtime**: Switch between blue/green without data loss
3. **Simple Rollback**: Roll back code while keeping data
4. **Consistent State**: Both environments see the same data

### Volume Configuration

**Docker Compose (both blue and green):**
```yaml
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

### Connection String

Both environments use the same connection string:
```
Data Source=/data/myfinance.db
```

## 📝 Database Migrations

### Migration Strategy

Entity Framework Core migrations are applied automatically when the application starts. For blue-green deployments with shared database:

1. **Backward Compatibility Required**: Migrations must be backward compatible
2. **Expand-Contract Pattern**: 
   - Deploy new version with additive changes
   - Remove old columns/tables in subsequent deployment
3. **No Breaking Changes**: Avoid renaming or removing columns used by old version

### Migration Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Deploy New Version to Green (Inactive)                   │
│    - Green starts and applies migrations                     │
│    - Blue (Active) continues running with same DB            │
│    - Migrations must be compatible with Blue's code          │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Test Green Environment                                   │
│    - Health checks pass                                      │
│    - Integration tests pass                                  │
│    - Both Blue and Green work with migrated DB               │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Switch Traffic to Green                                  │
│    - Nginx routes traffic to Green                           │
│    - Green becomes Active                                    │
│    - Blue becomes Inactive                                   │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Rollback Option Available                                │
│    - Can switch back to Blue if issues detected             │
│    - Blue still compatible with DB (backward compat)         │
└─────────────────────────────────────────────────────────────┘
```

### Example: Backward Compatible Migration

**❌ Breaking Change (Don't do this):**
```csharp
// Renaming column - breaks old version
migrationBuilder.RenameColumn(
    name: "Name",
    table: "Categories",
    newName: "CategoryName");
```

**✅ Backward Compatible (Do this):**
```csharp
// Step 1: Add new column (deployed in v1.1)
migrationBuilder.AddColumn<string>(
    name: "CategoryName",
    table: "Categories",
    nullable: true);

// Step 2: Application uses both Name and CategoryName
// Step 3: After v1.1 is stable, deploy v1.2 to remove old column
migrationBuilder.DropColumn(
    name: "Name",
    table: "Categories");
```

## 💾 Backup and Restore

### Backup Strategy

**Automated Backups:**
```bash
# Linux/macOS
./scripts/database/backup-db.sh

# Windows
scripts\database\backup-db.bat
```

**What Gets Backed Up:**
- Shared database file (`myfinance.db`)
- Timestamped backup in `backups/` directory
- Automatic cleanup (keeps last 10 backups)

**When to Backup:**
- Before major deployments
- Before applying database migrations
- Before any manual database operations
- On a scheduled basis (recommended: daily)

### Restore Process

```bash
# Linux/macOS
./scripts/database/restore-db.sh backups/myfinance-20240115-143000.db

# Windows
scripts\database\restore-db.bat backups\myfinance-20240115-143000.db
```

**Restore Steps:**
1. Creates safety backup of current database
2. Copies backup file to all running containers
3. Restarts containers to reload database
4. Verifies restore integrity

## 🔐 Data Integrity

### Concurrency Handling

SQLite uses file-level locking:
- **Write Operations**: One write at a time (serialized)
- **Read Operations**: Multiple concurrent reads allowed
- **WAL Mode**: Write-Ahead Logging for better concurrency

### Database File Locking

```
┌─────────────────────────────────────────────────────────────┐
│  Blue Container         Shared Volume        Green Container │
│  (Writing)              (myfinance.db)       (Reading)       │
│                                                               │
│  Write Request ────────► SQLite Locks ◄────── Read Request   │
│                          Database                            │
│  (Queued) ◄────────────  Returns Data ──────► (Success)      │
│                                                               │
│  Note: SQLite handles locking automatically                  │
└─────────────────────────────────────────────────────────────┘
```

### Data Consistency

- **ACID Compliance**: SQLite provides full ACID guarantees
- **Transactions**: All EF Core operations use transactions
- **Isolation**: Read Committed isolation level
- **Durability**: WAL mode ensures durability

## 📈 Scalability Considerations

### Current Setup (Single Host)

✅ **Suitable for:**
- Small to medium applications
- Single server deployments
- Development and testing
- Up to moderate concurrent users

⚠️ **Limitations:**
- Single server only (no horizontal scaling)
- SQLite file locking limits concurrent writes
- Volume must be on same host

### Future Migration Path

If you need to scale beyond a single server:

```
SQLite (Current)
    │
    ├─► PostgreSQL (Recommended for multi-server)
    ├─► MySQL/MariaDB
    └─► SQL Server
```

**Migration would require:**
1. Update connection strings
2. Change EF Core provider
3. Re-test migrations
4. Update backup scripts
5. Consider connection pooling

## 🛠️ Maintenance

### Regular Tasks

**Daily:**
- Monitor disk space (`df -h`)
- Check container logs

**Weekly:**
- Review backup retention
- Verify backup integrity

**Monthly:**
- Test restore procedure
- Review database size growth
- Clean old backups if needed

### Database Operations

**Check Database Size:**
```bash
docker exec myfinance-api-green ls -lh /data/myfinance.db
```

**View Database Contents:**
```bash
docker exec -it myfinance-api-green sqlite3 /data/myfinance.db
sqlite> .tables
sqlite> .schema
sqlite> .quit
```

**Optimize Database:**
```bash
docker exec myfinance-api-green sqlite3 /data/myfinance.db "VACUUM;"
```

## 📚 Best Practices

1. **Always Backup**: Create backup before migrations or deployments
2. **Test Migrations**: Test in blue/green inactive environment first
3. **Backward Compatibility**: Design migrations to support rollback
4. **Monitor Disk**: Keep eye on database file size
5. **Document Schema**: Keep schema documentation up to date
6. **Version Control**: Store migration scripts in git
7. **Automated Backups**: Schedule regular automated backups
8. **Test Restores**: Regularly test restore procedure

## 🔍 Troubleshooting

### Database Locked Error

**Symptom:**
```
database is locked
```

**Solution:**
- SQLite serializes writes automatically
- Application should retry on lock errors
- Check for long-running transactions

### Database File Not Found

**Symptom:**
```
unable to open database file
```

**Solution:**
```bash
# Check volume exists
docker volume ls | grep shared_api_data

# Check file in container
docker exec myfinance-api-green ls -la /data/

# Verify volume mount
docker inspect myfinance-api-green | grep Mounts -A 10
```

### Disk Space Issues

**Check Space:**
```bash
# On host
df -h

# In container
docker exec myfinance-api-green df -h /data
```

**Free Space:**
```bash
# Remove old backups
rm backups/myfinance-*.db

# Vacuum database
docker exec myfinance-api-green sqlite3 /data/myfinance.db "VACUUM;"
```

## 📞 Support Resources

- [Database Scripts README](../scripts/database/README.md)
- [Quick Reference](../DATABASE-QUICK-REF.md)
- [Deployment Guide](../DEPLOYMENT-GUIDE.md)
- [Blue-Green Flow](./blue-green-flow.md)

## 📄 License

Part of MyFinance Infrastructure - See main README for license information.
