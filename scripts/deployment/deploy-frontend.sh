#!/bin/bash

# Deploy Frontend to Specific Environment
# This script deploys the frontend application to blue or green environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Set registry (Jenkins also sets this in environment)
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io/rocsa65}"

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

# Check if image exists locally (from pipeline build)
if docker image inspect "${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}" >/dev/null 2>&1; then
    echo "✓ Using locally available image: ${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}"
else
    # Pull the latest image
    # Note: If packages are public, no authentication needed for pull
    echo "Pulling frontend image: ${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}"
    
    # Try pulling without authentication first (for public packages)
    if ! docker pull "${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}" 2>/dev/null; then
        echo "Pull without auth failed, attempting with credentials..."
        # If pull fails and credentials are available, try with authentication
        if [[ -n "$GITHUB_PACKAGES_TOKEN" && -n "$GITHUB_PACKAGES_USER" ]]; then
            echo "$GITHUB_PACKAGES_TOKEN" | docker login ghcr.io -u "$GITHUB_PACKAGES_USER" --password-stdin
            docker pull "${DOCKER_REGISTRY}/myfinance-client:${RELEASE_NUMBER}"
        else
            echo "❌ Error: Failed to pull image and no credentials available"
            echo "Ensure packages are public or set GITHUB_PACKAGES_USER and GITHUB_PACKAGES_TOKEN"
            exit 1
        fi
    fi
fi

# Stop existing container if running
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing $CONTAINER_NAME container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
fi

# Deploy to target environment
echo "Starting frontend in $TARGET_ENV environment..."
cd "$PROJECT_ROOT/docker/blue-green"

# Use --no-deps to avoid starting dependent services (API should already be running)
docker-compose -f "$(basename "$COMPOSE_FILE")" up -d --no-deps "$SERVICE_NAME"

# Wait for container to be ready
echo "Waiting for frontend to be ready..."

# Health check using container name (not localhost - we're inside Jenkins container)
MAX_RETRIES=30
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    # Check using container name on port 80 (internal container port)
    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_NAME}:80/" 2>/dev/null || echo "000")
    
    if [[ "$HEALTH_CHECK" == "200" ]]; then
        echo "✅ Frontend deployed successfully to $TARGET_ENV environment"
        echo "Release: $RELEASE_NUMBER"
        echo "Health check: $HEALTH_CHECK"
        
        # Log deployment (non-fatal if fails)
        mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Frontend $RELEASE_NUMBER deployed to $TARGET_ENV" >> "$PROJECT_ROOT/logs/deployment.log" 2>/dev/null || true
        
        exit 0
    fi
    
    echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES - Status: $HEALTH_CHECK"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo "❌ Frontend deployment to $TARGET_ENV failed - health check timeout"
echo "Check logs: docker logs $CONTAINER_NAME"

# Show recent logs
echo "Recent container logs:"
docker logs --tail 50 "$CONTAINER_NAME"

exit 1