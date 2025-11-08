#!/bin/bash

# Setup Infrastructure Script
# This script initializes the complete MyFinance infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Setting up MyFinance Infrastructure..."
echo "Project Root: $PROJECT_ROOT"

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/backup"
mkdir -p "$PROJECT_ROOT/notifications"

# Create external network for all services
echo "🌐 Creating Docker network..."
docker network create myfinance-network 2>/dev/null || echo "Network already exists"

# Set executable permissions on all scripts
echo "🔧 Setting script permissions..."
find "$PROJECT_ROOT/scripts" -name "*.sh" -exec chmod +x {} \;

# Load production environment
echo "🔧 Loading production environment..."
source "$PROJECT_ROOT/scripts/deployment/load-env.sh" production

echo "📋 Infrastructure setup checklist:"
echo "✅ Directory structure created"
echo "✅ Docker network created" 
echo "✅ Script permissions set"
echo "✅ Environment variables loaded"

echo ""
echo "🎯 Next steps:"
echo "1. Start Jenkins: cd jenkins/docker && docker-compose up -d"
echo "2. Start monitoring: cd monitoring && docker-compose up -d"
echo "3. Deploy blue environment: scripts/deployment/deploy-backend.sh blue <release>"
echo "4. Deploy frontend: scripts/deployment/deploy-frontend.sh blue <release>"
echo "5. Start nginx proxy: cd docker/nginx && docker-compose up -d"

echo ""
echo "🔗 Access URLs (after setup):"
echo "- Jenkins: http://localhost:8080 (admin/admin123)"
echo "- Grafana: http://localhost:3003 (admin/admin123)" 
echo "- Prometheus: http://localhost:9090"
echo "- Application: http://localhost (after deployment)"

echo ""
echo "📖 Documentation:"
echo "- See README.md for detailed setup instructions"
echo "- Check individual component READMEs in respective directories"

echo "✨ Infrastructure setup completed!"