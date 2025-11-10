#!/bin/bash

# Blue-Green Traffic Switch Script
# This script switches traffic between blue and green environments
# Usage: ./blue-green-switch.sh <blue|green> [api|client|both]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_ENV="$1"
SERVICE="${2:-both}"  # Default to 'both' if not specified

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <blue|green> [api|client|both]"
    exit 1
fi

if [[ "$SERVICE" != "api" && "$SERVICE" != "client" && "$SERVICE" != "both" ]]; then
    echo "Error: Service must be 'api', 'client', or 'both'"
    echo "Usage: $0 <blue|green> [api|client|both]"
    exit 1
fi

echo "Switching traffic to $TARGET_ENV environment for: $SERVICE"

# Backup current nginx configuration
NGINX_CONFIG="$PROJECT_ROOT/docker/nginx/blue-green.conf"
NGINX_BACKUP="$PROJECT_ROOT/docker/nginx/blue-green.conf.backup.$(date +%Y%m%d-%H%M%S)"

cp "$NGINX_CONFIG" "$NGINX_BACKUP"
echo "Backed up nginx configuration to $NGINX_BACKUP"

# Update nginx configuration
if [[ "$TARGET_ENV" == "green" ]]; then
    echo "Updating nginx to route traffic to green environment..."
    
    # Build sed command based on service
    SED_COMMANDS=""
    
    if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
        # Comment out blue (handle both commented and uncommented states)
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/# server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/'"
        # Uncomment green (remove any number of # at the start)
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*#[[:space:]]*server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/'"
    fi
    
    if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*server myfinance-client-blue:80;/# server myfinance-client-blue:80;/'"
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*#[[:space:]]*server myfinance-client-green:80;/server myfinance-client-green:80;/' -e 's/^# server myfinance-client-green:80;/server myfinance-client-green:80;/'"
    fi
    
    eval sed -i.tmp $SED_COMMANDS "$NGINX_CONFIG"
else
    echo "Updating nginx to route traffic to blue environment..."
    
    # Build sed command based on service
    SED_COMMANDS=""
    
    if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
        # Uncomment blue (remove any number of # at the start)
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*#[[:space:]]*server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;/'"
        # Comment out green (handle both commented and uncommented states)
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/# server myfinance-api-green:80 max_fails=1 fail_timeout=10s;/'"
    fi
    
    if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*#[[:space:]]*server myfinance-client-blue:80;/server myfinance-client-blue:80;/' -e 's/^# server myfinance-client-blue:80;/server myfinance-client-blue:80;/'"
        SED_COMMANDS="$SED_COMMANDS -e 's/^[[:space:]]*server myfinance-client-green:80;/# server myfinance-client-green:80;/'"
    fi
    
    eval sed -i.tmp $SED_COMMANDS "$NGINX_CONFIG"
fi

# Remove temporary file
rm -f "$NGINX_CONFIG.tmp"

# Copy the updated config file into the nginx container (since we use named volumes, not bind mounts)
echo "Copying updated configuration to nginx container..."
docker cp "$NGINX_CONFIG" myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf

# Verify nginx container is running
if ! docker ps | grep -q myfinance-nginx-proxy; then
    echo "Error: nginx container is not running"
    echo "This should not happen - nginx starts with Jenkins"
    echo "Try restarting the Jenkins stack: cd jenkins/docker && docker-compose restart"
    exit 1
fi

# Test and reload nginx configuration (this will fail if config file doesn't exist or has errors)
echo "Reloading nginx configuration..."
if docker exec myfinance-nginx-proxy nginx -t 2>&1; then
    docker exec myfinance-nginx-proxy nginx -s reload
    echo "nginx configuration reloaded successfully"
else
    echo "Error: nginx configuration test failed, restoring backup"
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    docker cp "$NGINX_BACKUP" myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
    exit 1
fi

# Update environment variable
export NGINX_UPSTREAM="$TARGET_ENV"

# Verify the switch
echo "Verifying traffic switch..."

# Only check backend if we're switching API traffic
if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
    echo "Waiting for backend to be ready..."
    
    # Wait for backend to actually respond (retry logic)
    MAX_RETRIES=12
    RETRY_COUNT=0
    BACKEND_READY=false
    
    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        sleep 5
        
        # Try to connect to the backend container directly by name (both containers on myfinance-network)
        BACKEND_CONTAINER="myfinance-api-${TARGET_ENV}"
        
        DIRECT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${BACKEND_CONTAINER}:80/health" 2>/dev/null || echo "000")
        
        if [[ "$DIRECT_HEALTH" == "200" ]]; then
            echo "✅ Backend $TARGET_ENV is responding (attempt $((RETRY_COUNT + 1)))"
            BACKEND_READY=true
            break
        else
            echo "⏳ Waiting for backend $TARGET_ENV to be ready... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES, status: $DIRECT_HEALTH)"
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
    
    if [[ "$BACKEND_READY" != "true" ]]; then
        echo "❌ Backend $TARGET_ENV did not become healthy in time"
        echo "Restoring previous nginx configuration..."
        cp "$NGINX_BACKUP" "$NGINX_CONFIG"
        docker cp "$NGINX_BACKUP" myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
        docker exec myfinance-nginx-proxy nginx -s reload
        exit 1
    fi
fi

# Now test through nginx

# Test health endpoints by curling from inside the nginx container itself
# This ensures we're testing the actual nginx routing
API_HEALTH="000"
if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
    echo "Testing API health endpoint..."
    API_HEALTH=$(docker exec myfinance-nginx-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost/health 2>/dev/null || echo "000")
    echo "API Health Response: $API_HEALTH"
fi

# Check if client is deployed (frontend) - check if any client server line is active (not commented)
CLIENT_HEALTH="000"
CLIENT_DEPLOYED=false
if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
    if grep -q "^\s*server myfinance-client-.*:80;" "$NGINX_CONFIG"; then
        echo "Testing Client health endpoint..."
        # Use Host header to ensure we hit the client server, not API server
        CLIENT_HEALTH=$(docker exec myfinance-nginx-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: myfinance.local" http://localhost/ 2>/dev/null || echo "000")
        echo "Client Health Response: $CLIENT_HEALTH"
        CLIENT_DEPLOYED=true
    else
        echo "Client: Not deployed (all client servers commented out)"
    fi
fi

# Verify health checks based on what we're switching
HEALTH_CHECK_FAILED=false

if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
    if [[ "$API_HEALTH" != "200" ]]; then
        echo "❌ API health check failed after switching to $TARGET_ENV"
        echo "API Health: $API_HEALTH (expected 200)"
        HEALTH_CHECK_FAILED=true
    fi
fi

if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
    if [[ "$CLIENT_DEPLOYED" == "true" && "$CLIENT_HEALTH" != "200" ]]; then
        echo "❌ Client health check failed after switching to $TARGET_ENV"
        echo "Client Health: $CLIENT_HEALTH (expected 200)"
        HEALTH_CHECK_FAILED=true
    fi
fi

if [[ "$HEALTH_CHECK_FAILED" == "true" ]]; then
    echo "Restoring previous nginx configuration..."
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    docker cp "$NGINX_BACKUP" myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
    docker exec myfinance-nginx-proxy nginx -s reload
    exit 1
fi

echo "✅ Traffic successfully switched to $TARGET_ENV environment"
if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
    echo "API Health: $API_HEALTH"
fi
if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
    if [[ "$CLIENT_DEPLOYED" == "true" ]]; then
        echo "Client Health: $CLIENT_HEALTH"
    else
        echo "Client: Not deployed (skipped)"
    fi
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

# Stop API container if we switched API
if [[ "$SERVICE" == "api" || "$SERVICE" == "both" ]]; then
    if docker ps | grep -q "myfinance-api-$INACTIVE_ENV"; then
        docker stop "myfinance-api-$INACTIVE_ENV"
        echo "✅ Stopped myfinance-api-$INACTIVE_ENV"
    fi
fi

# Stop client container if we switched client
if [[ "$SERVICE" == "client" || "$SERVICE" == "both" ]]; then
    if docker ps | grep -q "myfinance-client-$INACTIVE_ENV"; then
        docker stop "myfinance-client-$INACTIVE_ENV"
        echo "✅ Stopped myfinance-client-$INACTIVE_ENV"
    fi
fi

exit 0