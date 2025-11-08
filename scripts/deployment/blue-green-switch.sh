#!/bin/bash

# Blue-Green Traffic Switch Script
# This script switches traffic between blue and green environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment configuration
source "$SCRIPT_DIR/load-env.sh" production

TARGET_ENV="$1"

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <blue|green>"
    exit 1
fi

echo "Switching traffic to $TARGET_ENV environment..."

# Backup current nginx configuration
NGINX_CONFIG="$PROJECT_ROOT/docker/nginx/blue-green.conf"
NGINX_BACKUP="$PROJECT_ROOT/docker/nginx/blue-green.conf.backup.$(date +%Y%m%d-%H%M%S)"

cp "$NGINX_CONFIG" "$NGINX_BACKUP"
echo "Backed up nginx configuration to $NGINX_BACKUP"

# Update nginx configuration
if [[ "$TARGET_ENV" == "green" ]]; then
    echo "Updating nginx to route traffic to green environment..."
    sed -i.tmp \
        -e 's/server myfinance-api-blue:80;/# server myfinance-api-blue:80;/' \
        -e 's/# server myfinance-api-green:80;/server myfinance-api-green:80;/' \
        -e 's/server myfinance-client-blue:80;/# server myfinance-client-blue:80;/' \
        -e 's/# server myfinance-client-green:80;/server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
else
    echo "Updating nginx to route traffic to blue environment..."
    sed -i.tmp \
        -e 's/# server myfinance-api-blue:80;/server myfinance-api-blue:80;/' \
        -e 's/server myfinance-api-green:80;/# server myfinance-api-green:80;/' \
        -e 's/# server myfinance-client-blue:80;/server myfinance-client-blue:80;/' \
        -e 's/server myfinance-client-green:80;/# server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
fi

# Remove temporary file
rm -f "$NGINX_CONFIG.tmp"

# Reload nginx configuration
echo "Reloading nginx configuration..."
docker exec myfinance-nginx-proxy nginx -t
if [[ $? -eq 0 ]]; then
    docker exec myfinance-nginx-proxy nginx -s reload
    echo "nginx configuration reloaded successfully"
else
    echo "Error: nginx configuration test failed, restoring backup"
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    exit 1
fi

# Update environment variable
export NGINX_UPSTREAM="$TARGET_ENV"

# Verify the switch
echo "Verifying traffic switch..."
sleep 5

# Test health endpoints
API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health)
CLIENT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)

if [[ "$API_HEALTH" == "200" && "$CLIENT_HEALTH" == "200" ]]; then
    echo "✅ Traffic successfully switched to $TARGET_ENV environment"
    echo "API Health: $API_HEALTH"
    echo "Client Health: $CLIENT_HEALTH"
    
    # Log the switch
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Traffic switched to $TARGET_ENV" >> "$PROJECT_ROOT/logs/traffic-switch.log"
    
    # Update current environment file
    echo "$TARGET_ENV" > "$PROJECT_ROOT/current-environment.txt"
    
    exit 0
else
    echo "❌ Health check failed after switching to $TARGET_ENV"
    echo "API Health: $API_HEALTH"
    echo "Client Health: $CLIENT_HEALTH"
    
    # Restore backup
    echo "Restoring previous nginx configuration..."
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    docker exec myfinance-nginx-proxy nginx -s reload
    
    exit 1
fi