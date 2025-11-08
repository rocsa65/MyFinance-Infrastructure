#!/bin/bash

# Production Monitor Script
# This script monitors the production environment for a specified duration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MONITOR_DURATION_SECONDS="${1:-600}"  # Default 10 minutes
CURRENT_ENV="blue"

# Get current active environment
if [[ -f "$PROJECT_ROOT/current-environment.txt" ]]; then
    CURRENT_ENV=$(cat "$PROJECT_ROOT/current-environment.txt")
fi

echo "Monitoring production environment ($CURRENT_ENV) for $MONITOR_DURATION_SECONDS seconds..."

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Monitor configuration
CHECK_INTERVAL=30  # Check every 30 seconds
MAX_FAILURES=3     # Trigger rollback after 3 consecutive failures

START_TIME=$(date +%s)
END_TIME=$((START_TIME + MONITOR_DURATION_SECONDS))
FAILURE_COUNT=0

echo "Monitoring started at $(date)"
echo "Will monitor until $(date -d "@$END_TIME")"

# Log monitoring start
echo "$(date '+%Y-%m-%d %H:%M:%S') - Production monitoring started for $MONITOR_DURATION_SECONDS seconds on $CURRENT_ENV" >> "$PROJECT_ROOT/logs/monitoring.log"

while [[ $(date +%s) -lt $END_TIME ]]; do
    CURRENT_TIME=$(date +%s)
    REMAINING_TIME=$((END_TIME - CURRENT_TIME))
    
    echo "⏱️  Monitoring... $REMAINING_TIME seconds remaining (Failures: $FAILURE_COUNT/$MAX_FAILURES)"
    
    # Perform comprehensive health check
    if "$SCRIPT_DIR/health-check.sh" system "$CURRENT_ENV" > /dev/null 2>&1; then
        echo "✅ Health check passed at $(date '+%H:%M:%S')"
        FAILURE_COUNT=0  # Reset failure counter on success
        
        # Additional performance checks
        echo "📊 Performance metrics:"
        
        # Check response times
        API_RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://localhost/api/health 2>/dev/null || echo "timeout")
        CLIENT_RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://localhost/ 2>/dev/null || echo "timeout")
        
        echo "   - API response time: ${API_RESPONSE_TIME}s"
        echo "   - Client response time: ${CLIENT_RESPONSE_TIME}s"
        
        # Check memory usage
        if [[ "$CURRENT_ENV" == "green" ]]; then
            API_MEMORY=$(docker stats --no-stream --format "table {{.MemUsage}}" myfinance-api-green | tail -1 || echo "N/A")
            CLIENT_MEMORY=$(docker stats --no-stream --format "table {{.MemUsage}}" myfinance-client-green | tail -1 || echo "N/A")
        else
            API_MEMORY=$(docker stats --no-stream --format "table {{.MemUsage}}" myfinance-api-blue | tail -1 || echo "N/A")
            CLIENT_MEMORY=$(docker stats --no-stream --format "table {{.MemUsage}}" myfinance-client-blue | tail -1 || echo "N/A")
        fi
        
        echo "   - API memory usage: $API_MEMORY"
        echo "   - Client memory usage: $CLIENT_MEMORY"
        
        # Log successful check
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Production monitoring check PASSED on $CURRENT_ENV (API: ${API_RESPONSE_TIME}s, Client: ${CLIENT_RESPONSE_TIME}s)" >> "$PROJECT_ROOT/logs/monitoring.log"
        
    else
        ((FAILURE_COUNT++))
        echo "❌ Health check failed at $(date '+%H:%M:%S') - Failure $FAILURE_COUNT/$MAX_FAILURES"
        
        # Log failed check
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Production monitoring check FAILED on $CURRENT_ENV (Failure $FAILURE_COUNT/$MAX_FAILURES)" >> "$PROJECT_ROOT/logs/monitoring.log"
        
        if [[ $FAILURE_COUNT -ge $MAX_FAILURES ]]; then
            echo "🚨 CRITICAL: $MAX_FAILURES consecutive failures detected!"
            echo "Initiating emergency rollback..."
            
            # Log critical failure
            echo "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL: $MAX_FAILURES consecutive failures on $CURRENT_ENV - Initiating rollback" >> "$PROJECT_ROOT/logs/monitoring.log"
            
            # Determine rollback target
            if [[ "$CURRENT_ENV" == "green" ]]; then
                ROLLBACK_TARGET="blue"
            else
                ROLLBACK_TARGET="green"
            fi
            
            # Execute emergency rollback
            "$SCRIPT_DIR/../deployment/emergency-rollback.sh" "$ROLLBACK_TARGET"
            
            # Send critical notification
            "$SCRIPT_DIR/notify-failure.sh" "production-monitor" "Emergency rollback triggered after $MAX_FAILURES consecutive failures"
            
            exit 1
        fi
    fi
    
    # Wait before next check
    sleep $CHECK_INTERVAL
done

echo "🎉 Production monitoring completed successfully!"
echo "Duration: $MONITOR_DURATION_SECONDS seconds"
echo "Total failures: $FAILURE_COUNT"

# Final health check
echo "Performing final health verification..."
if "$SCRIPT_DIR/health-check.sh" system "$CURRENT_ENV" > /dev/null 2>&1; then
    echo "✅ Final health check passed"
    
    # Log successful completion
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Production monitoring completed successfully on $CURRENT_ENV (Total failures: $FAILURE_COUNT)" >> "$PROJECT_ROOT/logs/monitoring.log"
    
    # Send success notification
    "$SCRIPT_DIR/notify-success.sh" "production-monitor" "Production monitoring completed successfully on $CURRENT_ENV environment"
    
    exit 0
else
    echo "❌ Final health check failed"
    
    # Log final failure
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Production monitoring completed with FINAL FAILURE on $CURRENT_ENV" >> "$PROJECT_ROOT/logs/monitoring.log"
    
    # Send warning notification
    "$SCRIPT_DIR/notify-failure.sh" "production-monitor" "Production monitoring completed but final health check failed"
    
    exit 1
fi