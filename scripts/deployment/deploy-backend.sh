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

# Set environment-specific variables
if [[ "$TARGET_ENV" == "green" ]]; then
    export GREEN_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.green.yml"
    API_CONTAINER_NAME="myfinance-api-green"
    DB_CONTAINER_NAME="myfinance-db-green"
    DB_PORT="5434"
    API_SERVICE_NAME="myfinance-api-green"
    DB_SERVICE_NAME="myfinance-db-green"
    export DB_CONNECTION_STRING_GREEN="Server=myfinance-db-green;Database=myfinance_green;User Id=${DB_USER};Password=${DB_PASSWORD};"
else
    export BLUE_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.blue.yml"
    API_CONTAINER_NAME="myfinance-api-blue"
    DB_CONTAINER_NAME="myfinance-db-blue"
    DB_PORT="5433"
    API_SERVICE_NAME="myfinance-api-blue"
    DB_SERVICE_NAME="myfinance-db-blue"
    export DB_CONNECTION_STRING="${DB_CONNECTION_STRING:-Server=myfinance-db-blue;Database=myfinance_blue;User Id=${DB_USER};Password=${DB_PASSWORD};}"
fi

# Create network if it doesn't exist
docker network create myfinance-network 2>/dev/null || true

# Pull the latest image
echo "Pulling backend image: ${DOCKER_REGISTRY}/myfinance-api:${RELEASE_NUMBER}"
docker pull "${DOCKER_REGISTRY}/myfinance-api:${RELEASE_NUMBER}"

# Stop existing containers if running
for container in "$API_CONTAINER_NAME" "$DB_CONTAINER_NAME"; do
    if docker ps -q -f name="$container" | grep -q .; then
        echo "Stopping existing $container container..."
        docker stop "$container"
        docker rm "$container"
    fi
done

# Deploy to target environment
echo "Starting backend services in $TARGET_ENV environment..."
cd "$PROJECT_ROOT/docker/blue-green"

# Start database first
docker-compose -f "$(basename "$COMPOSE_FILE")" up -d "$DB_SERVICE_NAME"

# Wait for database to be ready
echo "Waiting for database to be ready..."
MAX_DB_RETRIES=30
DB_RETRY_COUNT=0

while [[ $DB_RETRY_COUNT -lt $MAX_DB_RETRIES ]]; do
    if docker exec "$DB_CONTAINER_NAME" pg_isready -U "$DB_USER" -d "myfinance_${TARGET_ENV}" >/dev/null 2>&1; then
        echo "✅ Database is ready"
        break
    fi
    
    echo "Database check attempt $((DB_RETRY_COUNT + 1))/$MAX_DB_RETRIES"
    sleep 5
    ((DB_RETRY_COUNT++))
done

if [[ $DB_RETRY_COUNT -eq $MAX_DB_RETRIES ]]; then
    echo "❌ Database failed to start in $TARGET_ENV environment"
    docker logs --tail 50 "$DB_CONTAINER_NAME"
    exit 1
fi

# Start API service
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
        echo "Database: myfinance_${TARGET_ENV}"
        
        # Log deployment
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
echo "Check DB logs: docker logs $DB_CONTAINER_NAME"

# Show recent logs
echo "Recent API logs:"
docker logs --tail 50 "$API_CONTAINER_NAME"

echo "Recent DB logs:"
docker logs --tail 20 "$DB_CONTAINER_NAME"

exit 1