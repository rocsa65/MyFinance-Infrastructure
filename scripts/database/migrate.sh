#!/bin/bash

# Database Migration Script for SQLite
# This script runs Entity Framework migrations on the target environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_ENV="$1"

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <blue|green>"
    exit 1
fi

echo "Running database migrations on $TARGET_ENV environment..."

# Set environment-specific variables
API_CONTAINER_NAME="myfinance-api-$TARGET_ENV"
DB_FILE="finance_$TARGET_ENV.db"

# Check if API container is running
if ! docker ps -q -f name="$API_CONTAINER_NAME" | grep -q .; then
    echo "Error: API container '$API_CONTAINER_NAME' is not running"
    exit 1
fi

# Backup database before migration if it exists
echo "Creating database backup before migration..."
mkdir -p "$PROJECT_ROOT/backup"
BACKUP_FILE="$PROJECT_ROOT/backup/pre-migration-$TARGET_ENV-$(date +%Y%m%d-%H%M%S).db"

if docker exec "$API_CONTAINER_NAME" test -f "/data/$DB_FILE" 2>/dev/null; then
    docker cp "$API_CONTAINER_NAME:/data/$DB_FILE" "$BACKUP_FILE" 2>/dev/null || {
        echo "Warning: Could not create backup"
    }
    echo "✅ Backup created: $(basename "$BACKUP_FILE")"
else
    echo "No existing database to backup (will be created during migration)"
fi

# Run migrations through the API container
echo "Running Entity Framework migrations..."

MIGRATION_RESULT=$(docker exec "$API_CONTAINER_NAME" dotnet ef database update --no-build 2>&1)
MIGRATION_EXIT_CODE=$?

if [[ $MIGRATION_EXIT_CODE -eq 0 ]]; then
    echo "✅ Database migrations completed successfully"
    echo "Migration output:"
    echo "$MIGRATION_RESULT"
    
    # Log migration
    mkdir -p "$PROJECT_ROOT/logs"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SQLite database migration completed on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log"
    
    # Verify database file was created/updated
    echo "Verifying database file..."
    if docker exec "$API_CONTAINER_NAME" test -f "/data/$DB_FILE" 2>/dev/null; then
        DB_SIZE=$(docker exec "$API_CONTAINER_NAME" stat -c%s "/data/$DB_FILE" 2>/dev/null || echo "0")
        echo "✅ Database file exists: $DB_FILE (size: $DB_SIZE bytes)"
    else
        echo "⚠️  Warning: Database file not found after migration"
    fi
    
    # Test API connectivity post-migration
    echo "Testing API connectivity after migration..."
    sleep 10
    
    API_HEALTH=$(docker exec "$API_CONTAINER_NAME" curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null || echo "000")
    
    if [[ "$API_HEALTH" == "200" ]]; then
        echo "✅ API health check passed after migration"
    else
        echo "❌ API health check failed after migration: $API_HEALTH"
        echo "Migration may have caused issues"
    fi
    
    exit 0
else
    echo "❌ Database migrations failed"
    echo "Migration error output:"
    echo "$MIGRATION_RESULT"
    
    # Log migration failure
    mkdir -p "$PROJECT_ROOT/logs"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SQLite database migration FAILED on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log"
    echo "Error: $MIGRATION_RESULT" >> "$PROJECT_ROOT/logs/migration.log"
    
    # Attempt to restore backup if available
    if [[ -f "$BACKUP_FILE" ]]; then
        echo "Attempting to restore database backup..."
        docker cp "$BACKUP_FILE" "$API_CONTAINER_NAME:/data/$DB_FILE" || {
            echo "❌ Failed to restore database backup"
        }
        echo "Database backup restored, please restart the API container"
    fi
    
    exit 1
fi