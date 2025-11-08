#!/bin/bash

# Database Replication Script
# This script replicates data from blue to green environment (or vice versa)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOURCE_ENV="$1"
TARGET_ENV="$2"

# Default: replicate from blue to green
if [[ -z "$SOURCE_ENV" ]]; then
    SOURCE_ENV="blue"
fi

if [[ -z "$TARGET_ENV" ]]; then
    TARGET_ENV="green"
fi

if [[ "$SOURCE_ENV" == "$TARGET_ENV" ]]; then
    echo "Error: Source and target environments must be different"
    echo "Usage: $0 [source_env] [target_env]"
    echo "Example: $0 blue green"
    exit 1
fi

if [[ "$SOURCE_ENV" != "blue" && "$SOURCE_ENV" != "green" ]] || [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Environments must be 'blue' or 'green'"
    echo "Usage: $0 [blue|green] [blue|green]"
    exit 1
fi

echo "Replicating database from $SOURCE_ENV to $TARGET_ENV environment..."

# Set environment-specific variables
SOURCE_DB_CONTAINER="myfinance-db-$SOURCE_ENV"
TARGET_DB_CONTAINER="myfinance-db-$TARGET_ENV"
SOURCE_DB_NAME="myfinance_$SOURCE_ENV"
TARGET_DB_NAME="myfinance_$TARGET_ENV"

# Source environment configuration
source "$SCRIPT_DIR/../deployment/load-env.sh" production

# Check if source container is running
if ! docker ps -q -f name="$SOURCE_DB_CONTAINER" | grep -q .; then
    echo "Error: Source database container '$SOURCE_DB_CONTAINER' is not running"
    exit 1
fi

# Check if target container is running
if ! docker ps -q -f name="$TARGET_DB_CONTAINER" | grep -q .; then
    echo "Error: Target database container '$TARGET_DB_CONTAINER' is not running"
    exit 1
fi

# Create backup directory
mkdir -p "$PROJECT_ROOT/backup"

# Wait for both databases to be ready
echo "Checking database readiness..."
for container in "$SOURCE_DB_CONTAINER" "$TARGET_DB_CONTAINER"; do
    MAX_RETRIES=30
    RETRY_COUNT=0
    
    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if [[ "$container" == *"blue"* ]]; then
            DB_NAME="myfinance_blue"
        else
            DB_NAME="myfinance_green"
        fi
        
        if docker exec "$container" pg_isready -U "${DB_USER}" -d "$DB_NAME" >/dev/null 2>&1; then
            echo "✅ $container is ready"
            break
        fi
        
        echo "Waiting for $container - attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
        sleep 5
        ((RETRY_COUNT++))
    done
    
    if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
        echo "❌ $container is not ready"
        exit 1
    fi
done

# Create backup of target database
echo "Creating backup of target database ($TARGET_ENV)..."
TARGET_BACKUP_FILE="$PROJECT_ROOT/backup/pre-replication-$TARGET_ENV-$(date +%Y%m%d-%H%M%S).sql"
docker exec "$TARGET_DB_CONTAINER" pg_dump -U "${DB_USER}" -d "$TARGET_DB_NAME" > "$TARGET_BACKUP_FILE" 2>/dev/null || {
    echo "Warning: Could not backup target database"
}

# Create dump of source database
echo "Creating dump of source database ($SOURCE_ENV)..."
DUMP_FILE="$PROJECT_ROOT/backup/replication-$SOURCE_ENV-to-$TARGET_ENV-$(date +%Y%m%d-%H%M%S).sql"
docker exec "$SOURCE_DB_CONTAINER" pg_dump -U "${DB_USER}" -d "$SOURCE_DB_NAME" > "$DUMP_FILE"

if [[ ! -f "$DUMP_FILE" || ! -s "$DUMP_FILE" ]]; then
    echo "❌ Failed to create database dump"
    exit 1
fi

echo "✅ Source database dump created: $(basename "$DUMP_FILE")"

# Stop target API to prevent connections during restoration
TARGET_API_CONTAINER="myfinance-api-$TARGET_ENV"
API_WAS_RUNNING=false

if docker ps -q -f name="$TARGET_API_CONTAINER" | grep -q .; then
    echo "Stopping target API container for safe restoration..."
    docker stop "$TARGET_API_CONTAINER"
    API_WAS_RUNNING=true
fi

# Drop and recreate target database
echo "Recreating target database ($TARGET_ENV)..."
docker exec "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d postgres -c "DROP DATABASE IF EXISTS $TARGET_DB_NAME;"
docker exec "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d postgres -c "CREATE DATABASE $TARGET_DB_NAME OWNER ${DB_USER};"

# Restore dump to target database
echo "Restoring data to target database ($TARGET_ENV)..."
docker exec -i "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d "$TARGET_DB_NAME" < "$DUMP_FILE"
RESTORE_EXIT_CODE=$?

if [[ $RESTORE_EXIT_CODE -eq 0 ]]; then
    echo "✅ Database replication completed successfully"
    
    # Verify restoration
    echo "Verifying data replication..."
    
    SOURCE_COUNT=$(docker exec "$SOURCE_DB_CONTAINER" psql -U "${DB_USER}" -d "$SOURCE_DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' \n')
    TARGET_COUNT=$(docker exec "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d "$TARGET_DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' \n')
    
    echo "Source tables: $SOURCE_COUNT"
    echo "Target tables: $TARGET_COUNT"
    
    if [[ "$SOURCE_COUNT" == "$TARGET_COUNT" && "$SOURCE_COUNT" != "0" ]]; then
        echo "✅ Data replication verification passed"
        
        # Log replication
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Database replicated from $SOURCE_ENV to $TARGET_ENV" >> "$PROJECT_ROOT/logs/replication.log"
        
        # Restart target API if it was running
        if [[ "$API_WAS_RUNNING" == "true" ]]; then
            echo "Restarting target API container..."
            docker start "$TARGET_API_CONTAINER"
            
            # Wait for API to be ready
            echo "Waiting for API to be ready..."
            sleep 30
            
            MAX_API_RETRIES=10
            API_RETRY_COUNT=0
            
            while [[ $API_RETRY_COUNT -lt $MAX_API_RETRIES ]]; do
                API_HEALTH=$(docker exec "$TARGET_API_CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null || echo "000")
                
                if [[ "$API_HEALTH" == "200" ]]; then
                    echo "✅ Target API is healthy after replication"
                    break
                fi
                
                echo "API health check $((API_RETRY_COUNT + 1))/$MAX_API_RETRIES - Status: $API_HEALTH"
                sleep 10
                ((API_RETRY_COUNT++))
            done
            
            if [[ $API_RETRY_COUNT -eq $MAX_API_RETRIES ]]; then
                echo "⚠️  Target API may not be healthy after replication"
            fi
        fi
        
        # Clean up old dump file (keep backup)
        rm -f "$DUMP_FILE"
        
        exit 0
    else
        echo "❌ Data replication verification failed"
        echo "Table counts don't match or are zero"
    fi
else
    echo "❌ Database restoration failed"
    
    # Attempt to restore target backup
    if [[ -f "$TARGET_BACKUP_FILE" ]]; then
        echo "Attempting to restore target database backup..."
        docker exec "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d postgres -c "DROP DATABASE IF EXISTS $TARGET_DB_NAME;"
        docker exec "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d postgres -c "CREATE DATABASE $TARGET_DB_NAME OWNER ${DB_USER};"
        docker exec -i "$TARGET_DB_CONTAINER" psql -U "${DB_USER}" -d "$TARGET_DB_NAME" < "$TARGET_BACKUP_FILE"
        echo "Target database backup restored"
    fi
fi

# Restart target API if it was running
if [[ "$API_WAS_RUNNING" == "true" ]]; then
    echo "Restarting target API container..."
    docker start "$TARGET_API_CONTAINER"
fi

exit 1