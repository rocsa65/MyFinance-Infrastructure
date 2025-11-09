#!/bin/bash

# Rollback Notification Script
# This script sends notifications about rollback events

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ROLLBACK_TARGET="$1"
ROLLBACK_STATUS="$2"

if [[ -z "$ROLLBACK_TARGET" || -z "$ROLLBACK_STATUS" ]]; then
    echo "Usage: $0 <environment> <SUCCESS|FAILED>"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Prepare notification message
if [[ "$ROLLBACK_STATUS" == "SUCCESS" ]]; then
    EMOJI="✅"
    SEVERITY="INFO"
    MESSAGE="Rollback to $ROLLBACK_TARGET environment completed successfully"
else
    EMOJI="🚨"
    SEVERITY="CRITICAL"
    MESSAGE="Rollback to $ROLLBACK_TARGET environment FAILED"
fi

# Log notification
echo "$TIMESTAMP [$SEVERITY] $MESSAGE" >> "$PROJECT_ROOT/logs/notifications.log"

# Console output
echo "$EMOJI $MESSAGE"

# Send notification via different channels
# (Uncomment and configure as needed)

# 1. Slack Notification (requires SLACK_WEBHOOK_URL)
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    SLACK_PAYLOAD=$(cat <<EOF
{
    "text": "$EMOJI MyFinance Rollback Notification",
    "attachments": [
        {
            "color": "$([ "$ROLLBACK_STATUS" == "SUCCESS" ] && echo "good" || echo "danger")",
            "fields": [
                {
                    "title": "Environment",
                    "value": "$ROLLBACK_TARGET",
                    "short": true
                },
                {
                    "title": "Status",
                    "value": "$ROLLBACK_STATUS",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$TIMESTAMP",
                    "short": false
                }
            ]
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$SLACK_PAYLOAD" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || echo "Failed to send Slack notification"
fi

# 2. Email Notification (requires configured mail server)
if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail &> /dev/null; then
    SUBJECT="[MyFinance] Rollback $ROLLBACK_STATUS - $ROLLBACK_TARGET"
    BODY="Rollback to $ROLLBACK_TARGET environment: $ROLLBACK_STATUS at $TIMESTAMP"
    
    echo "$BODY" | mail -s "$SUBJECT" "$NOTIFICATION_EMAIL" 2>/dev/null || \
        echo "Failed to send email notification"
fi

# 3. Discord Notification (requires DISCORD_WEBHOOK_URL)
if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    DISCORD_COLOR=$([ "$ROLLBACK_STATUS" == "SUCCESS" ] && echo "3066993" || echo "15158332")
    DISCORD_PAYLOAD=$(cat <<EOF
{
    "embeds": [{
        "title": "$EMOJI MyFinance Rollback Notification",
        "description": "$MESSAGE",
        "color": $DISCORD_COLOR,
        "fields": [
            {
                "name": "Environment",
                "value": "$ROLLBACK_TARGET",
                "inline": true
            },
            {
                "name": "Status",
                "value": "$ROLLBACK_STATUS",
                "inline": true
            },
            {
                "name": "Timestamp",
                "value": "$TIMESTAMP",
                "inline": false
            }
        ]
    }]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$DISCORD_PAYLOAD" \
        "$DISCORD_WEBHOOK_URL" 2>/dev/null || echo "Failed to send Discord notification"
fi

# 4. Write to system log
if command -v logger &> /dev/null; then
    logger -t myfinance-rollback -p user.$SEVERITY "$MESSAGE"
fi

# 5. Create alert file for monitoring systems
ALERT_FILE="$PROJECT_ROOT/logs/rollback-alert-$(date +%Y%m%d-%H%M%S).json"
cat > "$ALERT_FILE" <<EOF
{
    "timestamp": "$TIMESTAMP",
    "event": "rollback",
    "environment": "$ROLLBACK_TARGET",
    "status": "$ROLLBACK_STATUS",
    "severity": "$SEVERITY",
    "message": "$MESSAGE"
}
EOF

echo "Notification sent and logged"
echo "Alert file: $ALERT_FILE"

exit 0
