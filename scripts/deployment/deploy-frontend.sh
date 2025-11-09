#!/bin/bash

# Deploy Frontend to Specific Environment
# This script deploys the frontend application to blue or green environment

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

echo "Deploying frontend to $TARGET_ENV environment with release $RELEASE_NUMBER..."

# Set environment-specific variables
if [[ "$TARGET_ENV" == "green" ]]; then
    export GREEN_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.green.yml"
    CONTAINER_NAME="myfinance-client-green"
    SERVICE_NAME="myfinance-client-green"
else
    export BLUE_RELEASE_NUMBER="$RELEASE_NUMBER"
    COMPOSE_FILE="$PROJECT_ROOT/docker/blue-green/docker-compose.blue.yml"
    CONTAINER_NAME="myfinance-client-blue"
    SERVICE_NAME="myfinance-client-blue"
fi

# Create network if it doesn't exist
docker network create myfinance-network 2>/dev/null || true

# Pull the latest image
echo "Pulling frontend image: ${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}"
docker pull "${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}"

# Stop existing container if running
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing $CONTAINER_NAME container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
fi

# Deploy to target environment
echo "Starting frontend in $TARGET_ENV environment..."
cd "$PROJECT_ROOT/docker/blue-green"

docker-compose -f "$(basename "$COMPOSE_FILE")" up -d "$SERVICE_NAME"

# Wait for container to be ready
echo "Waiting for frontend to be ready..."
sleep 30

# Health check
MAX_RETRIES=30
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if [[ "$TARGET_ENV" == "green" ]]; then
        HEALTH_CHECK=$(docker exec myfinance-client-green curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
    else
        HEALTH_CHECK=$(docker exec myfinance-client-blue curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
    fi
    
    if [[ "$HEALTH_CHECK" == "200" ]]; then
        echo "✅ Frontend deployed successfully to $TARGET_ENV environment"
        echo "Release: $RELEASE_NUMBER"
        echo "Health check: $HEALTH_CHECK"
        
        # Log deployment
        mkdir -p "$PROJECT_ROOT/logs"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Frontend $RELEASE_NUMBER deployed to $TARGET_ENV" >> "$PROJECT_ROOT/logs/deployment.log"
        
        exit 0
    fi
    
    echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES - Status: $HEALTH_CHECK"
    sleep 10
    ((RETRY_COUNT++))
done

echo "❌ Frontend deployment to $TARGET_ENV failed - health check timeout"
echo "Check logs: docker logs $CONTAINER_NAME"

# Show recent logs
echo "Recent container logs:"
docker logs --tail 50 "$CONTAINER_NAME"

exit 1