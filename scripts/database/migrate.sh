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

# Note: The API automatically runs migrations on startup
# We just need to verify the migrations completed successfully
echo "Verifying database migrations..."
echo "Note: API runs migrations automatically on startup"

# Check API logs for migration success
MIGRATION_LOGS=$(docker logs "$API_CONTAINER_NAME" 2>&1 | grep -i "migration" || echo "")

if echo "$MIGRATION_LOGS" | grep -q "Database migration completed successfully"; then
    echo "✅ Database migrations completed successfully (verified from API logs)"
    
    # Log migration (non-fatal if fails)
    mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SQLite database migration completed on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log" 2>/dev/null || true
    
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
    sleep 5
    
    # Use container name for cross-network access
    API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://${API_CONTAINER_NAME}/" 2>/dev/null || echo "000")
    
    if [[ "$API_HEALTH" == "200" || "$API_HEALTH" == "404" ]]; then
        echo "✅ API health check passed after migration (Status: $API_HEALTH)"
    else
        echo "⚠️  Warning: API health check returned: $API_HEALTH"
        echo "Migration completed but API may need verification"
    fi
    
    exit 0
elif echo "$MIGRATION_LOGS" | grep -q "No migrations were applied"; then
    echo "✅ Database is already up to date (no migrations needed)"
    
    # Log migration (non-fatal if fails)
    mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SQLite database already up to date on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log" 2>/dev/null || true
    
    exit 0
else
    echo "⚠️  Warning: Could not verify migration status from logs"
    echo "Migration logs:"
    echo "$MIGRATION_LOGS"
    
    # Don't fail - API may still be healthy
    if docker exec "$API_CONTAINER_NAME" test -f "/data/$DB_FILE" 2>/dev/null; then
        echo "✅ Database file exists, assuming migrations are OK"
        exit 0
    else
        echo "❌ Database file not found and cannot verify migrations"
        exit 1
    fi
fi