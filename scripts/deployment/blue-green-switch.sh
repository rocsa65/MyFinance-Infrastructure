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
        -e 's/server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/# server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/' \
        -e 's/# server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/' \
        -e 's/server myfinance-client-blue:80;/# server myfinance-client-blue:80;/' \
        -e 's/# server myfinance-client-green:80;/server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
else
    echo "Updating nginx to route traffic to blue environment..."
    sed -i.tmp \
        -e 's/# server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/' \
        -e 's/server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/# server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/' \
        -e 's/# server myfinance-client-blue:80;/server myfinance-client-blue:80;/' \
        -e 's/server myfinance-client-green:80;/# server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
fi

# Remove temporary file
rm -f "$NGINX_CONFIG.tmp"

# Verify nginx container is running
if ! docker ps | grep -q myfinance-nginx-proxy; then
    echo "Error: nginx container is not running. Starting it now..."
    cd "$PROJECT_ROOT/docker/nginx"
    docker-compose up -d
    sleep 3
fi

# Verify config file exists in nginx container
echo "Verifying config file in nginx container..."
if ! docker exec myfinance-nginx-proxy test -f /etc/nginx/conf.d/default.conf; then
    echo "Error: Config file not found in nginx container"
    echo "This usually means the volume mount is broken. Restarting nginx..."
    cd "$PROJECT_ROOT/docker/nginx"
    docker-compose restart
    sleep 3
fi

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

# Test health endpoints by curling from inside the nginx container itself
# This ensures we're testing the actual nginx routing
echo "Testing API health endpoint..."
API_HEALTH=$(docker exec myfinance-nginx-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost/health 2>/dev/null || echo "000")
echo "API Health Response: $API_HEALTH"

# Check if client is deployed (frontend)
CLIENT_DEPLOYED=false
if grep -q "upstream myfinance_client" "$NGINX_CONFIG" && ! grep -q "^# upstream myfinance_client" "$NGINX_CONFIG"; then
    echo "Testing Client health endpoint..."
    CLIENT_HEALTH=$(docker exec myfinance-nginx-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost/ 2>/dev/null || echo "000")
    echo "Client Health Response: $CLIENT_HEALTH"
    CLIENT_DEPLOYED=true
fi

# Verify health checks
if [[ "$API_HEALTH" == "200" ]]; then
    if [[ "$CLIENT_DEPLOYED" == "true" && "$CLIENT_HEALTH" != "200" ]]; then
        echo "❌ Client health check failed after switching to $TARGET_ENV"
        echo "API Health: $API_HEALTH"
        echo "Client Health: $CLIENT_HEALTH"
        
        # Restore backup
        echo "Restoring previous nginx configuration..."
        cp "$NGINX_BACKUP" "$NGINX_CONFIG"
        docker exec myfinance-nginx-proxy nginx -s reload
        exit 1
    fi
    
    echo "✅ Traffic successfully switched to $TARGET_ENV environment"
    echo "API Health: $API_HEALTH"
    if [[ "$CLIENT_DEPLOYED" == "true" ]]; then
        echo "Client Health: $CLIENT_HEALTH"
    else
        echo "Client: Not deployed (skipped)"
    fi
    
    # Log the switch
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Traffic switched to $TARGET_ENV" >> "$PROJECT_ROOT/logs/traffic-switch.log"
    
    # Update current environment file
    echo "$TARGET_ENV" > "$PROJECT_ROOT/current-environment.txt"
    
    # Stop the inactive environment to save resources
    INACTIVE_ENV=""
    if [[ "$TARGET_ENV" == "blue" ]]; then
        INACTIVE_ENV="green"
    else
        INACTIVE_ENV="blue"
    fi
    
    echo "Stopping inactive $INACTIVE_ENV environment containers..."
    
    # Stop API container
    if docker ps | grep -q "myfinance-api-$INACTIVE_ENV"; then
        docker stop "myfinance-api-$INACTIVE_ENV"
        echo "✅ Stopped myfinance-api-$INACTIVE_ENV"
    fi
    
    # Stop client container if it exists
    if docker ps | grep -q "myfinance-client-$INACTIVE_ENV"; then
        docker stop "myfinance-client-$INACTIVE_ENV"
        echo "✅ Stopped myfinance-client-$INACTIVE_ENV"
    fi
    
    exit 0
else
    echo "❌ API health check failed after switching to $TARGET_ENV"
    echo "API Health: $API_HEALTH (expected 200)"
    
    if [[ "$API_HEALTH" == "000" ]]; then
        echo "⚠️  Connection failed - nginx may not be routing correctly or backend is unreachable"
        echo "Debugging information:"
        echo "- Check if nginx is running: docker ps | grep nginx"
        echo "- Check nginx logs: docker logs myfinance-nginx-proxy"
        echo "- Check backend container: docker ps | grep myfinance-api-$TARGET_ENV"
        echo "- Test direct backend: curl http://localhost:500$([[ $TARGET_ENV == 'blue' ]] && echo 1 || echo 2)/health"
    fi
    
    # Restore backup
    echo "Restoring previous nginx configuration..."
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    docker exec myfinance-nginx-proxy nginx -s reload
    
    exit 1
fi