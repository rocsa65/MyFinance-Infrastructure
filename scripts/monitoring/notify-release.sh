#!/bin/bash

# Notification Script for Release Events
# This script sends notifications about release success/failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STATUS="$1"           # success or failure
RELEASE_NUMBER="$2"   # Release version
MESSAGE="$3"          # Optional custom message

if [[ -z "$STATUS" || -z "$RELEASE_NUMBER" ]]; then
    echo "Error: Status and release number are required"
    echo "Usage: $0 <success|failure> <release-number> [message]"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEFAULT_MESSAGE="Release $RELEASE_NUMBER $STATUS"
NOTIFICATION_MESSAGE="${MESSAGE:-$DEFAULT_MESSAGE}"

echo "Sending $STATUS notification for release $RELEASE_NUMBER..."

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Log notification
echo "$TIMESTAMP - NOTIFICATION: $STATUS - $NOTIFICATION_MESSAGE" >> "$PROJECT_ROOT/logs/notifications.log"

# Console notification
if [[ "$STATUS" == "success" ]]; then
    echo "🎉 SUCCESS: $NOTIFICATION_MESSAGE"
    echo "✅ Release $RELEASE_NUMBER completed successfully at $TIMESTAMP"
else
    echo "💥 FAILURE: $NOTIFICATION_MESSAGE"
    echo "❌ Release $RELEASE_NUMBER failed at $TIMESTAMP"
fi

# Webhook notification (if configured)
if [[ -n "$WEBHOOK_URL" ]]; then
    echo "Sending webhook notification to $WEBHOOK_URL"
    
    WEBHOOK_PAYLOAD="{
        \"text\": \"MyFinance Release $STATUS\",
        \"attachments\": [
            {
                \"color\": \"$([ "$STATUS" == "success" ] && echo "good" || echo "danger")\",
                \"fields\": [
                    {
                        \"title\": \"Release Number\",
                        \"value\": \"$RELEASE_NUMBER\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Status\",
                        \"value\": \"$STATUS\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Timestamp\",
                        \"value\": \"$TIMESTAMP\",
                        \"short\": true
                    },
                    {
                        \"title\": \"Message\",
                        \"value\": \"$NOTIFICATION_MESSAGE\",
                        \"short\": false
                    }
                ]
            }
        ]
    }"
    
    curl -X POST -H "Content-type: application/json" \
         --data "$WEBHOOK_PAYLOAD" \
         "$WEBHOOK_URL" 2>/dev/null || echo "Webhook notification failed"
fi

# Email notification (if configured)
if [[ -n "$SMTP_SERVER" && -n "$NOTIFICATION_EMAIL" ]]; then
    echo "Sending email notification to $NOTIFICATION_EMAIL"
    
    SUBJECT="MyFinance Release $RELEASE_NUMBER - $STATUS"
    BODY="Release Details:
    
Release Number: $RELEASE_NUMBER
Status: $STATUS
Timestamp: $TIMESTAMP
Message: $NOTIFICATION_MESSAGE

This is an automated notification from the MyFinance deployment system."

    # Simple email using mail command (requires mailutils)
    echo "$BODY" | mail -s "$SUBJECT" "$NOTIFICATION_EMAIL" 2>/dev/null || echo "Email notification failed"
fi

# File-based notification for Jenkins
NOTIFICATION_FILE="$PROJECT_ROOT/notifications/release-$RELEASE_NUMBER.json"
mkdir -p "$(dirname "$NOTIFICATION_FILE")"

cat > "$NOTIFICATION_FILE" << EOF
{
    "release_number": "$RELEASE_NUMBER",
    "status": "$STATUS",
    "timestamp": "$TIMESTAMP",
    "message": "$NOTIFICATION_MESSAGE"
}
EOF

echo "Notification completed - details saved to $(basename "$NOTIFICATION_FILE")"

exit 0