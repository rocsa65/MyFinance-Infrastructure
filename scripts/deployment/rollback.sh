#!/bin/bash

# Emergency Rollback Script
# This script performs an immediate rollback to the blue environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ROLLBACK_TARGET="${1:-blue}"

echo "🚨 EMERGENCY ROLLBACK INITIATED 🚨"
echo "Rolling back to $ROLLBACK_TARGET environment..."
echo "Timestamp: $(date)"

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Log the rollback
echo "$(date '+%Y-%m-%d %H:%M:%S') - EMERGENCY ROLLBACK to $ROLLBACK_TARGET initiated" >> "$PROJECT_ROOT/logs/rollback.log"

# Get current environment
CURRENT_ENV="green"
if [[ -f "$PROJECT_ROOT/current-environment.txt" ]]; then
    CURRENT_ENV=$(cat "$PROJECT_ROOT/current-environment.txt")
fi

echo "Current environment: $CURRENT_ENV"
echo "Rolling back to: $ROLLBACK_TARGET"

# Backup current nginx configuration
NGINX_CONFIG="$PROJECT_ROOT/docker/nginx/blue-green.conf"
NGINX_BACKUP="$PROJECT_ROOT/docker/nginx/blue-green.conf.rollback.$(date +%Y%m%d-%H%M%S)"

cp "$NGINX_CONFIG" "$NGINX_BACKUP"
echo "Backed up nginx configuration to $NGINX_BACKUP"

# Switch traffic immediately
echo "Switching traffic to $ROLLBACK_TARGET environment..."

if [[ "$ROLLBACK_TARGET" == "blue" ]]; then
    sed -i.tmp \
        -e 's/# server myfinance-api-blue:80;/server myfinance-api-blue:80;/' \
        -e 's/server myfinance-api-green:80;/# server myfinance-api-green:80;/' \
        -e 's/# server myfinance-client-blue:80;/server myfinance-client-blue:80;/' \
        -e 's/server myfinance-client-green:80;/# server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
else
    sed -i.tmp \
        -e 's/server myfinance-api-blue:80;/# server myfinance-api-blue:80;/' \
        -e 's/# server myfinance-api-green:80;/server myfinance-api-green:80;/' \
        -e 's/server myfinance-client-blue:80;/# server myfinance-client-blue:80;/' \
        -e 's/# server myfinance-client-green:80;/server myfinance-client-green:80;/' \
        "$NGINX_CONFIG"
fi

# Remove temporary file
rm -f "$NGINX_CONFIG.tmp"

# Reload nginx immediately
echo "Reloading nginx configuration..."
docker exec myfinance-nginx-proxy nginx -t
if [[ $? -eq 0 ]]; then
    docker exec myfinance-nginx-proxy nginx -s reload
    echo "✅ nginx configuration reloaded successfully"
else
    echo "❌ nginx configuration test failed"
    exit 1
fi

# Verify rollback
echo "Verifying rollback..."
sleep 5

# Test health endpoints multiple times to ensure stability
for i in {1..5}; do
    API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health || echo "000")
    CLIENT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
    
    echo "Health check $i/5 - API: $API_HEALTH, Client: $CLIENT_HEALTH"
    
    if [[ "$API_HEALTH" != "200" || "$CLIENT_HEALTH" != "200" ]]; then
        echo "❌ Health check failed during rollback verification"
        if [[ $i -lt 5 ]]; then
            echo "Retrying in 5 seconds..."
            sleep 5
        fi
    else
        echo "✅ Health check passed"
        break
    fi
done

# Final verification
API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health || echo "000")
CLIENT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")

if [[ "$API_HEALTH" == "200" && "$CLIENT_HEALTH" == "200" ]]; then
    echo "✅ EMERGENCY ROLLBACK SUCCESSFUL"
    echo "Traffic successfully rolled back to $ROLLBACK_TARGET environment"
    echo "API Health: $API_HEALTH"
    echo "Client Health: $CLIENT_HEALTH"
    
    # Update current environment
    echo "$ROLLBACK_TARGET" > "$PROJECT_ROOT/current-environment.txt"
    
    # Log success
    echo "$(date '+%Y-%m-%d %H:%M:%S') - EMERGENCY ROLLBACK to $ROLLBACK_TARGET SUCCESSFUL" >> "$PROJECT_ROOT/logs/rollback.log"
    
    # Send notification
    "$SCRIPT_DIR/../monitoring/notify-rollback.sh" "$ROLLBACK_TARGET" "SUCCESS"
    
    exit 0
else
    echo "❌ EMERGENCY ROLLBACK FAILED"
    echo "API Health: $API_HEALTH"
    echo "Client Health: $CLIENT_HEALTH"
    
    # Log failure
    echo "$(date '+%Y-%m-%d %H:%M:%S') - EMERGENCY ROLLBACK to $ROLLBACK_TARGET FAILED" >> "$PROJECT_ROOT/logs/rollback.log"
    
    # Send critical notification
    "$SCRIPT_DIR/../monitoring/notify-rollback.sh" "$ROLLBACK_TARGET" "FAILED"
    
    # Try to restore backup
    echo "Attempting to restore backup configuration..."
    cp "$NGINX_BACKUP" "$NGINX_CONFIG"
    docker exec myfinance-nginx-proxy nginx -s reload
    
    exit 1
fi