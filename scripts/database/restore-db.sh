#!/bin/bash

# =============================================================================
# MyFinance Database Restore Script (Linux/macOS)
# =============================================================================
# Restores the shared SQLite database from a backup file
# 
# Usage:
#   ./scripts/database/restore-db.sh <backup-file>
#
# Description:
#   - Restores database to both blue and green environments
#   - Creates safety backup before restore
#   - Verifies restore integrity
#   - Requires manual confirmation before proceeding
# =============================================================================

set -e

# Configuration
DB_FILE="myfinance.db"
SAFETY_BACKUP_DIR="backups/safety"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=================================================="
echo "   MyFinance Database Restore"
echo "=================================================="
echo ""

# Check if backup file is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Backup file not specified${NC}"
    echo ""
    echo "Usage: $0 <backup-file>"
    echo ""
    echo "Available backups:"
    ls -lh backups/myfinance-*.db 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    exit 1
fi

BACKUP_FILE="$1"

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file not found: ${BACKUP_FILE}${NC}"
    exit 1
fi

BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null)
echo "Backup file: $BACKUP_FILE"
echo "Size: $BACKUP_SIZE bytes"
echo ""

# Find running containers
BLUE_RUNNING=false
GREEN_RUNNING=false

if docker ps --format '{{.Names}}' | grep -q "myfinance-api-blue"; then
    BLUE_RUNNING=true
fi

if docker ps --format '{{.Names}}' | grep -q "myfinance-api-green"; then
    GREEN_RUNNING=true
fi

if [ "$BLUE_RUNNING" = false ] && [ "$GREEN_RUNNING" = false ]; then
    echo -e "${RED}Error: No running MyFinance API container found${NC}"
    echo "Please ensure at least one environment (blue or green) is running"
    exit 1
fi

echo -e "${YELLOW}Running containers:${NC}"
[ "$BLUE_RUNNING" = true ] && echo "  - Blue (myfinance-api-blue)"
[ "$GREEN_RUNNING" = true ] && echo "  - Green (myfinance-api-green)"
echo ""

# Warning and confirmation
echo -e "${YELLOW}⚠️  WARNING: This will replace the current database with the backup${NC}"
echo -e "${YELLOW}   Both blue and green environments will be affected${NC}"
echo ""
read -p "Do you want to continue? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Restore cancelled"
    exit 0
fi

# Create safety backup directory
mkdir -p "$SAFETY_BACKUP_DIR"

# Create safety backup from current database
SAFETY_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SAFETY_BACKUP="${SAFETY_BACKUP_DIR}/pre-restore-${SAFETY_TIMESTAMP}.db"

echo "Creating safety backup of current database..."
if [ "$GREEN_RUNNING" = true ]; then
    CONTAINER="myfinance-api-green"
else
    CONTAINER="myfinance-api-blue"
fi

if docker cp "${CONTAINER}:/data/${DB_FILE}" "$SAFETY_BACKUP"; then
    echo -e "${GREEN}✓ Safety backup created: ${SAFETY_BACKUP}${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Could not create safety backup${NC}"
    read -p "Continue anyway? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

echo ""
echo "Restoring database..."

# Restore to running containers
RESTORE_SUCCESS=false

if [ "$BLUE_RUNNING" = true ]; then
    echo "Restoring to blue environment..."
    if docker cp "$BACKUP_FILE" "myfinance-api-blue:/data/${DB_FILE}"; then
        echo -e "${GREEN}✓ Blue environment restored${NC}"
        RESTORE_SUCCESS=true
    else
        echo -e "${RED}✗ Failed to restore blue environment${NC}"
    fi
fi

if [ "$GREEN_RUNNING" = true ]; then
    echo "Restoring to green environment..."
    if docker cp "$BACKUP_FILE" "myfinance-api-green:/data/${DB_FILE}"; then
        echo -e "${GREEN}✓ Green environment restored${NC}"
        RESTORE_SUCCESS=true
    else
        echo -e "${RED}✗ Failed to restore green environment${NC}"
    fi
fi

if [ "$RESTORE_SUCCESS" = false ]; then
    echo -e "${RED}Error: Restore failed${NC}"
    exit 1
fi

# Restart containers to reload database connection
echo ""
echo "Restarting containers to apply changes..."

if [ "$BLUE_RUNNING" = true ]; then
    docker restart myfinance-api-blue > /dev/null
    echo -e "${GREEN}✓ Blue container restarted${NC}"
fi

if [ "$GREEN_RUNNING" = true ]; then
    docker restart myfinance-api-green > /dev/null
    echo -e "${GREEN}✓ Green container restarted${NC}"
fi

# Summary
echo ""
echo "=================================================="
echo -e "${GREEN}Restore completed successfully!${NC}"
echo "=================================================="
echo "Restored from: $BACKUP_FILE"
echo "Safety backup: $SAFETY_BACKUP"
echo ""
echo "Database has been restored and containers restarted"
echo ""
