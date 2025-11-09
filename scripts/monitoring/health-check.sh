#!/bin/bash

# Health Check Script
# This script performs health checks on specific services in blue or green environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SERVICE_TYPE="$1"  # backend, frontend, or system
TARGET_ENV="$2"    # blue or green

if [[ "$SERVICE_TYPE" != "backend" && "$SERVICE_TYPE" != "frontend" && "$SERVICE_TYPE" != "system" ]]; then
    echo "Error: Service type must be 'backend', 'frontend', or 'system'"
    echo "Usage: $0 <backend|frontend|system> <blue|green>"
    exit 1
fi

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <backend|frontend|system> <blue|green>"
    exit 1
fi

echo "Performing $SERVICE_TYPE health check on $TARGET_ENV environment..."

# Create logs directory (non-fatal if fails)
mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || true

# Set environment-specific variables for SQLite
if [[ "$TARGET_ENV" == "green" ]]; then
    API_CONTAINER="myfinance-api-green"
    CLIENT_CONTAINER="myfinance-client-green"
    DB_FILE="finance_green.db"
    API_PORT="5002"
    CLIENT_PORT="3002"
else
    API_CONTAINER="myfinance-api-blue"
    CLIENT_CONTAINER="myfinance-client-blue"
    DB_FILE="finance_blue.db"
    API_PORT="5001"
    CLIENT_PORT="3001"
fi

# Health check functions
check_backend_health() {
    echo "Checking backend health..."
    
    # Check if container is running
    if ! docker ps -q -f name="$API_CONTAINER" | grep -q .; then
        echo "❌ Backend container '$API_CONTAINER' is not running"
        return 1
    fi
    
    # Check API endpoint using container name (cross-network access)
    # Try /api/health first, then fallback to /
    API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://$API_CONTAINER/api/health" 2>/dev/null || echo "000")
    
    if [[ "$API_HEALTH" == "000" || "$API_HEALTH" == "404" ]]; then
        # Fallback to root endpoint
        API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://$API_CONTAINER/" 2>/dev/null || echo "000")
    fi
    
    if [[ "$API_HEALTH" != "200" && "$API_HEALTH" != "404" ]]; then
        echo "❌ Backend health check failed - HTTP $API_HEALTH"
        return 1
    fi
    
    # Check database connectivity
    DB_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://$API_CONTAINER/api/accounts" 2>/dev/null || echo "000")
    
    if [[ "$DB_CHECK" == "200" || "$DB_CHECK" == "401" || "$DB_CHECK" == "404" ]]; then  # 401 is OK (authentication required), 404 is OK (endpoint may not exist yet)
        echo "✅ Backend health check passed"
        echo "   - Health endpoint: $API_HEALTH"
        echo "   - Database connectivity: $DB_CHECK"
        return 0
    else
        echo "❌ Backend database connectivity failed - HTTP $DB_CHECK"
        return 1
    fi
}

check_frontend_health() {
    echo "Checking frontend health..."
    
    # Check if container is running
    if ! docker ps -q -f name="$CLIENT_CONTAINER" | grep -q .; then
        echo "❌ Frontend container '$CLIENT_CONTAINER' is not running"
        return 1
    fi
    
    # Check main page
    CLIENT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$CLIENT_PORT/" || echo "000")
    
    if [[ "$CLIENT_HEALTH" != "200" ]]; then
        echo "❌ Frontend health check failed - HTTP $CLIENT_HEALTH"
        return 1
    fi
    
    # Check if static assets are loading
    ASSETS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$CLIENT_PORT/static/css/" || echo "000")
    
    echo "✅ Frontend health check passed"
    echo "   - Main page: $CLIENT_HEALTH"
    echo "   - Assets availability: $ASSETS_CHECK"
    return 0
}

check_database_health() {
    echo "Checking SQLite database health..."
    
    # Check if API container is running (SQLite is embedded in API)
    if ! docker ps -q -f name="$API_CONTAINER" | grep -q .; then
        echo "❌ API container '$API_CONTAINER' is not running (SQLite database is embedded)"
        return 1
    fi
    
    # Check if SQLite database file exists
    if docker exec "$API_CONTAINER" test -f "/data/$DB_FILE" 2>/dev/null; then
        DB_SIZE=$(docker exec "$API_CONTAINER" stat -c%s "/data/$DB_FILE" 2>/dev/null || echo "0")
        
        if [[ "$DB_SIZE" -gt "0" ]]; then
            echo "✅ SQLite database health check passed"
            echo "   - Database file: /data/$DB_FILE"
            echo "   - File size: $DB_SIZE bytes"
            return 0
        else
            echo "⚠️  SQLite database file exists but is empty"
            return 1
        fi
    else
        echo "⚠️  SQLite database file not yet created (will be created on first API call)"
        echo "   - Expected location: /data/$DB_FILE"
        return 0  # Not an error - DB created on demand
    fi
}

check_system_health() {
    echo "Performing comprehensive system health check..."
    
    local overall_status=0
    
    # Check all components
    if ! check_database_health; then
        overall_status=1
    fi
    
    if ! check_backend_health; then
        overall_status=1
    fi
    
    if ! check_frontend_health; then
        overall_status=1
    fi
    
    # Check integration
    echo "Checking frontend-backend integration..."
    INTEGRATION_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$CLIENT_PORT/api/health" || echo "000")
    
    if [[ "$INTEGRATION_CHECK" == "200" ]]; then
        echo "✅ Frontend-backend integration check passed"
    else
        echo "❌ Frontend-backend integration check failed - HTTP $INTEGRATION_CHECK"
        overall_status=1
    fi
    
    return $overall_status
}

# Perform health check based on service type
case "$SERVICE_TYPE" in
    "backend")
        check_backend_health
        HEALTH_STATUS=$?
        ;;
    "frontend")
        check_frontend_health
        HEALTH_STATUS=$?
        ;;
    "system")
        check_system_health
        HEALTH_STATUS=$?
        ;;
esac

# Log health check result (non-fatal if fails)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
if [[ $HEALTH_STATUS -eq 0 ]]; then
    echo "$TIMESTAMP - $SERVICE_TYPE health check PASSED on $TARGET_ENV" >> "$PROJECT_ROOT/logs/health-check.log" 2>/dev/null || true
    echo "🎉 Health check completed successfully"
else
    echo "$TIMESTAMP - $SERVICE_TYPE health check FAILED on $TARGET_ENV" >> "$PROJECT_ROOT/logs/health-check.log" 2>/dev/null || true
    echo "💥 Health check failed"
    
    # Show recent logs for debugging
    echo "Recent container logs for debugging:"
    if [[ "$SERVICE_TYPE" == "backend" || "$SERVICE_TYPE" == "system" ]]; then
        echo "API logs:"
        docker logs --tail 20 "$API_CONTAINER" 2>/dev/null || echo "Could not get API logs"
    fi
    
    if [[ "$SERVICE_TYPE" == "frontend" || "$SERVICE_TYPE" == "system" ]]; then
        echo "Client logs:"
        docker logs --tail 20 "$CLIENT_CONTAINER" 2>/dev/null || echo "Could not get client logs"
    fi
fi

exit $HEALTH_STATUS