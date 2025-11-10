#!/bin/bash

# Complete Infrastructure Cleanup Script
# This script removes all containers, images, volumes, and networks for MyFinance

set -e

echo "=========================================="
echo "MyFinance Infrastructure - Complete Cleanup"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will remove:"
echo "   - All MyFinance containers (including Jenkins)"
echo "   - All MyFinance Docker images"
echo "   - All MyFinance volumes (data will be lost)"
echo "   - MyFinance network"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Stop and remove all MyFinance containers
echo "1. Stopping and removing containers..."
docker ps -a --filter "name=myfinance" --format "{{.Names}}" | while read container; do
    echo "   Stopping $container..."
    docker stop "$container" 2>/dev/null || true
    echo "   Removing $container..."
    docker rm "$container" 2>/dev/null || true
done

# Remove blue-green environment containers
for env in blue green; do
    for service in api client; do
        CONTAINER="myfinance-${service}-${env}"
        if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
            echo "   Stopping $CONTAINER..."
            docker stop "$CONTAINER" 2>/dev/null || true
            echo "   Removing $CONTAINER..."
            docker rm "$CONTAINER" 2>/dev/null || true
        fi
    done
done

echo "✅ Containers removed"
echo ""

# Remove MyFinance images
echo "2. Removing Docker images..."
docker images --format "{{.Repository}}:{{.Tag}}" | grep "myfinance" | while read image; do
    echo "   Removing image: $image"
    docker rmi "$image" 2>/dev/null || true
done

# Remove ghcr.io images
docker images --format "{{.Repository}}:{{.Tag}}" | grep "ghcr.io/rocsa65/myfinance" | while read image; do
    echo "   Removing image: $image"
    docker rmi "$image" 2>/dev/null || true
done

echo "✅ Images removed"
echo ""

# Remove volumes
echo "3. Removing Docker volumes..."
docker volume ls --format "{{.Name}}" | grep "myfinance\|jenkins\|nginx" | while read volume; do
    echo "   Removing volume: $volume"
    docker volume rm "$volume" 2>/dev/null || true
done

# Remove specific volumes by pattern
for volume in jenkins_data nginx_config nginx_main_config nginx_logs \
              blue_api_data blue_api_logs green_api_data green_api_logs \
              blue_client_data green_client_data; do
    if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
        echo "   Removing volume: $volume"
        docker volume rm "$volume" 2>/dev/null || true
    fi
done

echo "✅ Volumes removed"
echo ""

# Remove network
echo "4. Removing Docker network..."
if docker network ls --format "{{.Name}}" | grep -q "^myfinance-network$"; then
    echo "   Removing network: myfinance-network"
    docker network rm myfinance-network 2>/dev/null || true
fi

if docker network ls --format "{{.Name}}" | grep -q "^jenkins-network$"; then
    echo "   Removing network: jenkins-network"
    docker network rm jenkins-network 2>/dev/null || true
fi

echo "✅ Networks removed"
echo ""

# Clean up nginx backup files
echo "5. Cleaning up nginx backup files..."
BACKUP_COUNT=$(ls -1 docker/nginx/blue-green.conf.backup.* 2>/dev/null | wc -l)
if [[ $BACKUP_COUNT -gt 0 ]]; then
    rm -f docker/nginx/blue-green.conf.backup.*
    echo "   Removed $BACKUP_COUNT nginx backup files"
fi
echo "✅ Backup files cleaned"
echo ""

# Clean up log files
echo "6. Cleaning up log files..."
if [[ -d logs ]]; then
    rm -rf logs/*
    echo "   Cleared logs directory"
fi
echo "✅ Logs cleaned"
echo ""

# Clean up current-environment.txt
if [[ -f current-environment.txt ]]; then
    rm -f current-environment.txt
    echo "   Removed current-environment.txt"
fi

# Prune system (optional - removes dangling resources)
echo "7. Pruning Docker system..."
docker system prune -f
echo "✅ System pruned"
echo ""

echo "=========================================="
echo "✅ Cleanup Complete!"
echo "=========================================="
echo ""
echo "All MyFinance infrastructure has been removed."
echo ""
echo "To start fresh:"
echo "  1. Create the network: docker network create myfinance-network"
echo "  2. Start Jenkins: cd jenkins/docker && docker-compose up -d"
echo "  3. Access Jenkins at: http://localhost:8081"
echo "  4. Run backend deployment pipeline"
echo "  5. Run frontend deployment pipeline"
echo ""
