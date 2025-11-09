#!/bin/bash

# Script: notify-failure.sh
# Purpose: Send notification when deployment fails
# Usage: ./notify-failure.sh <service> <version>

set -euo pipefail

SERVICE=$1
VERSION=$2

echo "=========================================="
echo "❌ DEPLOYMENT FAILED"
echo "=========================================="
echo "Service: $SERVICE"
echo "Version: $VERSION"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""
echo "Check Jenkins console output for details"
echo "Consider rolling back to previous version"
echo ""

# Future: Add Slack/email notifications here
# Example:
# curl -X POST -H 'Content-type: application/json' \
#   --data "{\"text\":\"❌ Deployment Failed: $SERVICE v$VERSION\"}" \
#   $SLACK_WEBHOOK_URL

exit 0
