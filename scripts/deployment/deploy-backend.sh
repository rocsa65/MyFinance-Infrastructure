#!/bin/bash

# Deploy Backend to Specific Environment
# This script deploys the backend API to blue or green environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment configuration
source "$SCRIPT_DIR/load-env.sh" production

TARGET_ENV="$1"
RELEASE_NUMBER="$2"

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <blue|green> <release-number>"
    exit 1
fi

if [[ -z "$RELEASE_NUMBER" ]]; then
    echo "Error: Release number is required"
    echo "Usage: $0 <blue|green> <release-number>"
    exit 1
fi

echo "Deploying backend to $TARGET_ENV environment with release $RELEASE_NUMBER..."

# Set environment-specific variables for SQLite
if [[ "$TARGET_ENV" == "green" ]]; then
    export GREEN_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.green.yml"
    API_CONTAINER_NAME="myfinance-api-green"
    API_SERVICE_NAME="myfinance-api-green"
    DB_FILE="finance_green.db"
else
    export BLUE_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.blue.yml"
    API_CONTAINER_NAME="myfinance-api-blue"
    API_SERVICE_NAME="myfinance-api-blue"
    DB_FILE="finance_blue.db"
fi

# Create network if it doesn't exist
docker network create myfinance-network 2>/dev/null || true

# Pull the latest image (using myfinance-server for SQLite)
echo "Pulling backend image: ${DOCKER_REGISTRY}/myfinance-server:${RELEASE_NUMBER}"
docker pull "${DOCKER_REGISTRY}/myfinance-server:${RELEASE_NUMBER}"

# Stop existing API container if running
if docker ps -q -f name="$API_CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing $API_CONTAINER_NAME container..."
    docker stop "$API_CONTAINER_NAME"
    docker rm "$API_CONTAINER_NAME"
fi

# Deploy to target environment
echo "Starting backend API in $TARGET_ENV environment..."
cd "$PROJECT_ROOT/docker/blue-green"

# Start API service (SQLite database is embedded, no separate DB service)
docker-compose -f "$(basename "$COMPOSE_FILE")" up -d "$API_SERVICE_NAME"

# Wait for API to be ready
echo "Waiting for API to be ready..."
sleep 30

# Health check
MAX_RETRIES=30
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    HEALTH_CHECK=$(docker exec "$API_CONTAINER_NAME" curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
    
    if [[ "$HEALTH_CHECK" == "200" ]]; then
        echo "✅ Backend deployed successfully to $TARGET_ENV environment"
        echo "Release: $RELEASE_NUMBER"
        echo "Health check: $HEALTH_CHECK"
        echo "Database: /data/$DB_FILE (SQLite)"
        
        # Verify SQLite database file
        if docker exec "$API_CONTAINER_NAME" test -f "/data/$DB_FILE" 2>/dev/null; then
            DB_SIZE=$(docker exec "$API_CONTAINER_NAME" stat -c%s "/data/$DB_FILE" 2>/dev/null || echo "0")
            echo "SQLite database size: $DB_SIZE bytes"
        else
            echo "Note: Database file will be created on first API call"
        fi
        
        # Log deployment
        mkdir -p "$PROJECT_ROOT/logs"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backend $RELEASE_NUMBER deployed to $TARGET_ENV" >> "$PROJECT_ROOT/logs/deployment.log"
        
        # Test database connection
        echo "Testing database connection..."
        DB_TEST=$(docker exec "$API_CONTAINER_NAME" curl -s -o /dev/null -w "%{http_code}" http://localhost/api/accounts || echo "000")
        echo "Database connection test: $DB_TEST"
        
        exit 0
    fi
    
    echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES - Status: $HEALTH_CHECK"
    sleep 10
    ((RETRY_COUNT++))
done

echo "❌ Backend deployment to $TARGET_ENV failed - health check timeout"
echo "Check API logs: docker logs $API_CONTAINER_NAME"

# Show recent logs
echo "Recent API logs:"
docker logs --tail 50 "$API_CONTAINER_NAME"

exit 1