#!/bin/bash

# Blue-Green Infrastructure Initialization Script
# This script sets up the blue-green deployment infrastructure for the first time

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "================================================"
echo "MyFinance Blue-Green Infrastructure Setup"
echo "SQLite-based Deployment"
echo "================================================"
echo ""

# Check if .env file exists
ENV_FILE="$PROJECT_ROOT/environments/production/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Error: Environment file not found: $ENV_FILE"
    echo "Please create the .env file first"
    exit 1
fi

echo "✅ Environment file found: $ENV_FILE"

# Source environment variables
source "$SCRIPT_DIR/load-env.sh" production

echo ""
echo "Configuration:"
echo "  Docker Registry: $DOCKER_REGISTRY"
echo "  Network: ${NETWORK_NAME:-myfinance-network}"
echo ""

# Create necessary directories
echo "Creating required directories..."
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/backup"
echo "✅ Directories created"

# Create Docker network
echo ""
echo "Creating Docker network..."
NETWORK_NAME="${NETWORK_NAME:-myfinance-network}"
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "✅ Network '$NETWORK_NAME' already exists"
else
    docker network create "$NETWORK_NAME"
    echo "✅ Network '$NETWORK_NAME' created"
fi

# Check if nginx configuration exists
echo ""
echo "Checking nginx configuration..."
NGINX_CONFIG="$PROJECT_ROOT/docker/nginx/blue-green.conf"
if [[ ! -f "$NGINX_CONFIG" ]]; then
    echo "⚠️  Warning: nginx blue-green configuration not found: $NGINX_CONFIG"
    echo "You may need to create this file manually"
else
    echo "✅ nginx configuration found"
fi

# Initialize environment tracking
echo ""
echo "Initializing environment tracking..."
CURRENT_ENV_FILE="$PROJECT_ROOT/current-environment.txt"
if [[ ! -f "$CURRENT_ENV_FILE" ]]; then
    echo "blue" > "$CURRENT_ENV_FILE"
    echo "✅ Set initial active environment: blue"
else
    CURRENT=$(cat "$CURRENT_ENV_FILE")
    echo "✅ Current active environment: $CURRENT"
fi

# Check for required images
echo ""
echo "Checking Docker images..."
REQUIRED_IMAGES=(
    "${DOCKER_REGISTRY}/myfinance-server:${BLUE_RELEASE_NUMBER:-latest}"
    "${DOCKER_REGISTRY}/myfinance-client:${BLUE_RELEASE_NUMBER:-latest}"
)

MISSING_IMAGES=()
for image in "${REQUIRED_IMAGES[@]}"; do
    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "✅ Image found: $image"
    else
        echo "⚠️  Image not found locally: $image"
        MISSING_IMAGES+=("$image")
    fi
done

if [[ ${#MISSING_IMAGES[@]} -gt 0 ]]; then
    echo ""
    read -p "Pull missing images now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for image in "${MISSING_IMAGES[@]}"; do
            echo "Pulling $image..."
            docker pull "$image" || echo "⚠️  Failed to pull $image"
        done
    fi
fi

# Display deployment options
echo ""
echo "================================================"
echo "Initial Setup Complete!"
echo "================================================"
echo ""
echo "Next Steps:"
echo ""
echo "1. Deploy Blue Environment (Initial Production):"
echo "   cd $PROJECT_ROOT/scripts/deployment"
echo "   ./deploy-backend.sh blue ${BLUE_RELEASE_NUMBER:-latest}"
echo "   ./deploy-frontend.sh blue ${BLUE_RELEASE_NUMBER:-latest}"
echo ""
echo "2. Verify Blue Environment Health:"
echo "   cd $PROJECT_ROOT/scripts/monitoring"
echo "   ./health-check.sh system blue"
echo ""
echo "3. (Optional) Deploy Green Environment for Testing:"
echo "   cd $PROJECT_ROOT/scripts/deployment"
echo "   ./deploy-backend.sh green ${GREEN_RELEASE_NUMBER:-latest}"
echo "   ./deploy-frontend.sh green ${GREEN_RELEASE_NUMBER:-latest}"
echo ""
echo "4. Configure nginx for Blue-Green Switching:"
echo "   - Ensure nginx is running with blue-green.conf"
echo "   - Initial traffic should route to blue environment"
echo ""
echo "5. To Switch Traffic Between Environments:"
echo "   ./blue-green-switch.sh <blue|green>"
echo ""
echo "6. Database Management:"
echo "   - Replicate DB: cd scripts/database && ./replicate.sh blue green"
echo "   - Run Migrations: cd scripts/database && ./migrate.sh <blue|green>"
echo ""
echo "================================================"
echo "SQLite Database Locations:"
echo "  Blue:  /data/finance_blue.db (in container)"
echo "  Green: /data/finance_green.db (in container)"
echo ""
echo "Docker Volumes:"
echo "  - blue_api_data (Blue API data + SQLite DB)"
echo "  - green_api_data (Green API data + SQLite DB)"
echo "  - blue_api_logs, green_api_logs (Application logs)"
echo "================================================"
echo ""
echo "For help, see: $PROJECT_ROOT/README.md"
echo ""
