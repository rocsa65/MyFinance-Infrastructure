#!/bin/bash

# Database Migration Script
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
if [[ "$TARGET_ENV" == "green" ]]; then
    DB_CONTAINER_NAME="myfinance-db-green"
    API_CONTAINER_NAME="myfinance-api-green"
    DB_NAME="myfinance_green"
else
    DB_CONTAINER_NAME="myfinance-db-blue"
    API_CONTAINER_NAME="myfinance-api-blue"
    DB_NAME="myfinance_blue"
fi

# Check if database container is running
if ! docker ps -q -f name="$DB_CONTAINER_NAME" | grep -q .; then
    echo "Error: Database container '$DB_CONTAINER_NAME' is not running"
    exit 1
fi

# Check if API container is running
if ! docker ps -q -f name="$API_CONTAINER_NAME" | grep -q .; then
    echo "Error: API container '$API_CONTAINER_NAME' is not running"
    exit 1
fi

# Wait for database to be ready
echo "Waiting for database to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if docker exec "$DB_CONTAINER_NAME" pg_isready -U "${DB_USER}" -d "$DB_NAME" >/dev/null 2>&1; then
        echo "✅ Database is ready"
        break
    fi
    
    echo "Database readiness check $((RETRY_COUNT + 1))/$MAX_RETRIES"
    sleep 5
    ((RETRY_COUNT++))
done

if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
    echo "❌ Database is not ready for migrations"
    exit 1
fi

# Backup database before migration
echo "Creating database backup before migration..."
BACKUP_FILE="/backup/pre-migration-$(date +%Y%m%d-%H%M%S).sql"
docker exec "$DB_CONTAINER_NAME" pg_dump -U "${DB_USER}" -d "$DB_NAME" > "$PROJECT_ROOT/backup/$(basename "$BACKUP_FILE")" 2>/dev/null || {
    echo "Warning: Could not create backup (backup directory may not be mounted)"
}

# Run migrations through the API container
echo "Running Entity Framework migrations..."

MIGRATION_RESULT=$(docker exec "$API_CONTAINER_NAME" dotnet ef database update --no-build 2>&1)
MIGRATION_EXIT_CODE=$?

if [[ $MIGRATION_EXIT_CODE -eq 0 ]]; then
    echo "✅ Database migrations completed successfully"
    echo "Migration output:"
    echo "$MIGRATION_RESULT"
    
    # Log migration
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Database migration completed on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log"
    
    # Verify migration by checking database schema
    echo "Verifying migration..."
    SCHEMA_CHECK=$(docker exec "$DB_CONTAINER_NAME" psql -U "${DB_USER}" -d "$DB_NAME" -c "\dt" 2>/dev/null | grep -c "public" || echo "0")
    
    if [[ $SCHEMA_CHECK -gt 0 ]]; then
        echo "✅ Database schema verification passed"
    else
        echo "⚠️  Warning: Database schema verification inconclusive"
    fi
    
    # Test API connectivity post-migration
    echo "Testing API connectivity after migration..."
    sleep 10
    
    API_HEALTH=$(docker exec "$API_CONTAINER_NAME" curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
    
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Database migration FAILED on $TARGET_ENV" >> "$PROJECT_ROOT/logs/migration.log"
    echo "Error: $MIGRATION_RESULT" >> "$PROJECT_ROOT/logs/migration.log"
    
    # Attempt to restore backup if available
    if [[ -f "$PROJECT_ROOT/backup/$(basename "$BACKUP_FILE")" ]]; then
        echo "Attempting to restore database backup..."
        docker exec -i "$DB_CONTAINER_NAME" psql -U "${DB_USER}" -d "$DB_NAME" < "$PROJECT_ROOT/backup/$(basename "$BACKUP_FILE")" || {
            echo "❌ Failed to restore database backup"
        }
    fi
    
    exit 1
fi