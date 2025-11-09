#!/bin/bash

# Database Replication Script for SQLite
# This script replicates SQLite database from blue to green environment (or vice versa)

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

echo "Replicating SQLite database from $SOURCE_ENV to $TARGET_ENV environment..."

# Set environment-specific variables
SOURCE_API_CONTAINER="myfinance-api-$SOURCE_ENV"
TARGET_API_CONTAINER="myfinance-api-$TARGET_ENV"
SOURCE_DB_FILE="finance_$SOURCE_ENV.db"
TARGET_DB_FILE="finance_$TARGET_ENV.db"

# Source environment configuration
source "$SCRIPT_DIR/../deployment/load-env.sh" production

# Check if source container is running
if ! docker ps -q -f name="$SOURCE_API_CONTAINER" | grep -q .; then
    echo "Error: Source API container '$SOURCE_API_CONTAINER' is not running"
    exit 1
fi

# Check if target container is running
if ! docker ps -q -f name="$TARGET_API_CONTAINER" | grep -q .; then
    echo "Error: Target API container '$TARGET_API_CONTAINER' is not running"
    exit 1
fi

# Create backup directory
mkdir -p "$PROJECT_ROOT/backup"

# Check if source database file exists
echo "Checking source database..."
if ! docker exec "$SOURCE_API_CONTAINER" test -f "/data/$SOURCE_DB_FILE" 2>/dev/null; then
    echo "Error: Source database file '/data/$SOURCE_DB_FILE' does not exist in container '$SOURCE_API_CONTAINER'"
    exit 1
fi

echo "✅ Source database found"

# Create backup of target database if it exists
echo "Creating backup of target database ($TARGET_ENV)..."
TARGET_BACKUP_FILE="$PROJECT_ROOT/backup/pre-replication-$TARGET_ENV-$(date +%Y%m%d-%H%M%S).db"
if docker exec "$TARGET_API_CONTAINER" test -f "/data/$TARGET_DB_FILE" 2>/dev/null; then
    docker cp "$TARGET_API_CONTAINER:/data/$TARGET_DB_FILE" "$TARGET_BACKUP_FILE" 2>/dev/null || {
        echo "Warning: Could not backup target database"
    }
    echo "✅ Target database backup created"
else
    echo "No existing target database to backup"
fi

# Stop target API to prevent database locks during copy
TARGET_API_WAS_RUNNING=false
if docker ps -q -f name="$TARGET_API_CONTAINER" | grep -q .; then
    echo "Stopping target API container for safe database replication..."
    docker stop "$TARGET_API_CONTAINER"
    TARGET_API_WAS_RUNNING=true
    sleep 5
fi

# Copy source database file to local backup directory
echo "Copying source database ($SOURCE_ENV)..."
TEMP_DB_FILE="$PROJECT_ROOT/backup/replication-$SOURCE_ENV-to-$TARGET_ENV-$(date +%Y%m%d-%H%M%S).db"
docker cp "$SOURCE_API_CONTAINER:/data/$SOURCE_DB_FILE" "$TEMP_DB_FILE"

if [[ ! -f "$TEMP_DB_FILE" || ! -s "$TEMP_DB_FILE" ]]; then
    echo "❌ Failed to copy source database"
    if [[ "$TARGET_API_WAS_RUNNING" == "true" ]]; then
        docker start "$TARGET_API_CONTAINER"
    fi
    exit 1
fi

echo "✅ Source database copied: $(basename "$TEMP_DB_FILE")"

# Copy database to target container
echo "Copying database to target environment ($TARGET_ENV)..."
docker cp "$TEMP_DB_FILE" "$TARGET_API_CONTAINER:/data/$TARGET_DB_FILE"
COPY_EXIT_CODE=$?

if [[ $COPY_EXIT_CODE -eq 0 ]]; then
    echo "✅ Database replication completed successfully"
    
    # Verify database file in target container
    echo "Verifying database replication..."
    
    if docker exec "$TARGET_API_CONTAINER" test -f "/data/$TARGET_DB_FILE" 2>/dev/null; then
        TARGET_DB_SIZE=$(docker exec "$TARGET_API_CONTAINER" stat -c%s "/data/$TARGET_DB_FILE" 2>/dev/null || echo "0")
        echo "Target database size: $TARGET_DB_SIZE bytes"
        
        if [[ "$TARGET_DB_SIZE" -gt "0" ]]; then
            echo "✅ Database replication verification passed"
            
            # Log replication
            mkdir -p "$PROJECT_ROOT/logs"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - SQLite database replicated from $SOURCE_ENV to $TARGET_ENV" >> "$PROJECT_ROOT/logs/replication.log"
            
            # Restart target API
            if [[ "$TARGET_API_WAS_RUNNING" == "true" ]]; then
                echo "Restarting target API container..."
                docker start "$TARGET_API_CONTAINER"
                
                # Wait for API to be ready
                echo "Waiting for API to be ready..."
                sleep 30
                
                # Determine the port based on target environment
                if [[ "$TARGET_ENV" == "green" ]]; then
                    TARGET_API_PORT="5002"
                else
                    TARGET_API_PORT="5001"
                fi
                
                MAX_API_RETRIES=10
                API_RETRY_COUNT=0
                
                while [[ $API_RETRY_COUNT -lt $MAX_API_RETRIES ]]; do
                    # Use container name for cross-network access
                    API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://${TARGET_API_CONTAINER}/" 2>/dev/null || echo "000")
                    
                    if [[ "$API_HEALTH" == "200" || "$API_HEALTH" == "404" ]]; then
                        echo "✅ Target API is healthy after replication (Status: $API_HEALTH)"
                        break
                    fi
                    
                    echo "API health check $((API_RETRY_COUNT + 1))/$MAX_API_RETRIES - Status: $API_HEALTH"
                    sleep 10
                    API_RETRY_COUNT=$((API_RETRY_COUNT + 1))
                done
                
                if [[ $API_RETRY_COUNT -eq $MAX_API_RETRIES ]]; then
                    echo "⚠️  Target API may not be healthy after replication"
                fi
            fi
            
            # Clean up temporary database file
            rm -f "$TEMP_DB_FILE"
            
            exit 0
        else
            echo "❌ Database replication verification failed - file is empty"
        fi
    else
        echo "❌ Database file not found in target container"
    fi
else
    echo "❌ Database copy to target failed"
    
    # Attempt to restore target backup if available
    if [[ -f "$TARGET_BACKUP_FILE" ]]; then
        echo "Attempting to restore target database backup..."
        docker cp "$TARGET_BACKUP_FILE" "$TARGET_API_CONTAINER:/data/$TARGET_DB_FILE"
        echo "Target database backup restored"
    fi
fi

# Restart target API if it was running
if [[ "$TARGET_API_WAS_RUNNING" == "true" ]]; then
    echo "Restarting target API container..."
    docker start "$TARGET_API_CONTAINER"
fi

exit 1