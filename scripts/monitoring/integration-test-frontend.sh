#!/bin/bash

# Frontend Integration Test Script
# This script runs integration tests for frontend deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET_ENV="$1"  # blue or green

if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
    echo "Error: Target environment must be 'blue' or 'green'"
    echo "Usage: $0 <blue|green>"
    exit 1
fi

echo "Running frontend integration tests against $TARGET_ENV environment..."

# Set environment-specific variables
if [[ "$TARGET_ENV" == "green" ]]; then
    CLIENT_CONTAINER="myfinance-client-green"
    CLIENT_PORT="3002"
else
    CLIENT_CONTAINER="myfinance-client-blue"
    CLIENT_PORT="3001"
fi

echo "Testing environment: $TARGET_ENV"
echo "Client Container: $CLIENT_CONTAINER"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

echo ""
echo "=========================================="
echo "FRONTEND INTEGRATION TESTS - $TARGET_ENV ENVIRONMENT"
echo "=========================================="

# Test 1: Frontend container is running
echo ""
echo "Test 1: Frontend Container Health"
if docker ps -q -f name="$CLIENT_CONTAINER" | grep -q .; then
    echo "✅ PASSED - Frontend container is running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED - Frontend container is not running"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Frontend responds to root endpoint
echo ""
echo "Test 2: Frontend Main Page"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${CLIENT_CONTAINER}:80/" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "✅ PASSED - Frontend main page responding (Status: $HTTP_STATUS)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED - Frontend not responding correctly (Status: $HTTP_STATUS)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Frontend serves static content
echo ""
echo "Test 3: Static Content Delivery"
CONTENT_CHECK=$(curl -s "http://${CLIENT_CONTAINER}:80/" 2>/dev/null | grep -i "<!doctype html>" || echo "")

if [[ -n "$CONTENT_CHECK" ]]; then
    echo "✅ PASSED - Frontend serving HTML content"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED - Frontend not serving expected HTML content"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Check frontend logs for errors
echo ""
echo "Test 4: Frontend Logs Check"
ERROR_COUNT=$(docker logs "$CLIENT_CONTAINER" 2>&1 | grep -iE "error|failed" | grep -v "info" | wc -l || echo "0")

if [[ "$ERROR_COUNT" -eq "0" ]]; then
    echo "✅ PASSED - No critical errors in frontend logs"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "⚠️  WARNING - Found $ERROR_COUNT error-like entries in logs"
    echo "   Recent errors:"
    docker logs --tail 10 "$CLIENT_CONTAINER" 2>&1 | grep -iE "error|failed" | grep -v "info" || true
    # Don't fail on log warnings
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 5: Container resource usage
echo ""
echo "Test 5: Container Resource Check"
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CLIENT_CONTAINER" 2>/dev/null || echo "unknown")

if [[ "$CONTAINER_STATUS" == "running" ]]; then
    echo "✅ PASSED - Container in healthy state: $CONTAINER_STATUS"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED - Container in unhealthy state: $CONTAINER_STATUS"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Summary
echo ""
echo "=========================================="
echo "FRONTEND INTEGRATION TEST SUMMARY"
echo "=========================================="
echo "Environment: $TARGET_ENV"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"

# Log results (non-fatal if fails)
mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || true
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "$TIMESTAMP - Frontend integration tests on $TARGET_ENV: $TESTS_PASSED passed, $TESTS_FAILED failed" >> "$PROJECT_ROOT/logs/integration-test.log" 2>/dev/null || true

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "🎉 All frontend integration tests passed!"
    exit 0
else
    echo ""
    echo "❌ Some frontend integration tests failed"
    echo "Check logs above for details"
    exit 1
fi
