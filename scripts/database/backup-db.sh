#!/bin/bash

# =============================================================================
# MyFinance Database Backup Script (Linux/macOS)
# =============================================================================
# Creates a timestamped backup of the shared SQLite database
# 
# Usage:
#   ./scripts/database/backup-db.sh
#
# Description:
#   - Backs up the shared database file (myfinance.db) used by both blue and green environments
#   - Creates timestamped backup in backups/ directory
#   - Verifies backup integrity
#   - Retains last 10 backups automatically
# =============================================================================

set -e

# Configuration
BACKUP_DIR="backups"
DB_FILE="myfinance.db"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/myfinance-${TIMESTAMP}.db"
KEEP_BACKUPS=10

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=================================================="
echo "   MyFinance Database Backup"
echo "=================================================="
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Find running container (try green first, then blue)
CONTAINER_NAME=""
if docker ps --format '{{.Names}}' | grep -q "myfinance-api-green"; then
    CONTAINER_NAME="myfinance-api-green"
elif docker ps --format '{{.Names}}' | grep -q "myfinance-api-blue"; then
    CONTAINER_NAME="myfinance-api-blue"
else
    echo -e "${RED}Error: No running MyFinance API container found${NC}"
    echo "Please ensure either blue or green environment is running"
    exit 1
fi

echo -e "${YELLOW}Using container: ${CONTAINER_NAME}${NC}"
echo ""

# Backup database
echo "Backing up database..."
if docker cp "${CONTAINER_NAME}:/data/${DB_FILE}" "$BACKUP_FILE"; then
    echo -e "${GREEN}✓ Backup created: ${BACKUP_FILE}${NC}"
else
    echo -e "${RED}Error: Failed to create backup${NC}"
    exit 1
fi

# Verify backup
BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null)
if [ "$BACKUP_SIZE" -gt 0 ]; then
    echo -e "${GREEN}✓ Backup verified (${BACKUP_SIZE} bytes)${NC}"
else
    echo -e "${RED}Error: Backup file is empty or invalid${NC}"
    exit 1
fi

# Cleanup old backups
echo ""
echo "Cleaning up old backups (keeping last ${KEEP_BACKUPS})..."
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/myfinance-*.db 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$KEEP_BACKUPS" ]; then
    ls -1t "$BACKUP_DIR"/myfinance-*.db | tail -n +$((KEEP_BACKUPS + 1)) | xargs rm -f
    echo -e "${GREEN}✓ Old backups cleaned up${NC}"
else
    echo "No cleanup needed (${BACKUP_COUNT} backups total)"
fi

# Summary
echo ""
echo "=================================================="
echo -e "${GREEN}Backup completed successfully!${NC}"
echo "=================================================="
echo "Backup file: $BACKUP_FILE"
echo "Size: $BACKUP_SIZE bytes"
echo "Total backups: $(ls -1 "$BACKUP_DIR"/myfinance-*.db 2>/dev/null | wc -l)"
echo ""
echo "To restore this backup:"
echo "  ./scripts/database/restore-db.sh $BACKUP_FILE"
echo ""
