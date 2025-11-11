# Script Execution Flow

## Overview
The MyFinance deployment system provides two main Jenkins jobs:

1. **MyFinance/Backend-Release** - Deploy backend only
2. **MyFinance/Frontend-Release** - Deploy frontend only

Each job operates independently and can be triggered separately for granular control over deployments.

## 1. Release Pipeline Trigger (Jenkins)

### Backend Release
```bash
# Backend deployment pipeline:
/var/jenkins_home/pipelines/backend-release.groovy
```

### Frontend Release
```bash
# Frontend deployment pipeline:
/var/jenkins_home/pipelines/frontend-release.groovy
```

## 2. Backend Deployment Flow

### Stage 1: Determine Target Environment
```bash
# Pipeline automatically detects which environment is live
# by reading /var/jenkins_home/docker/nginx/blue-green.conf

# If blue is live → deploy to green
# If green is live → deploy to blue
# If none is live → deploy to green (first deployment)
```

### Stage 2: Build & Test
```bash
# Checkout staging branch from GitHub
# Build: dotnet build MyFinance.sln --configuration Release
# Test: dotnet test MyFinance.sln (unless SKIP_TESTS = true)
```

### Stage 3: Build & Push Docker Image
```bash
# Build Docker image with release number tag
docker build -t ghcr.io/rocsa65/myfinance-server:v20251111-044054-2 -f MyFinance.Api/Dockerfile .
docker tag ghcr.io/rocsa65/myfinance-server:v20251111-044054-2 ghcr.io/rocsa65/myfinance-server:latest

# Push to GitHub Container Registry (requires 'github-token' credential)
docker login ghcr.io -u <GITHUB_USER> --password-stdin
docker push ghcr.io/rocsa65/myfinance-server:v20251111-044054-2
docker push ghcr.io/rocsa65/myfinance-server:latest
```

### Stage 4: Update Production Branch
```bash
# Merge staging → production
# Create release tag: backend-v20251111-044054-2
# Push to GitHub
```

### Stage 5: Deploy to Target Environment
```bash
# Deploy backend to target environment (blue or green)
./scripts/deployment/deploy-backend.sh <target_env> <release_number>

# What this script does:
# ├── Pull Docker image from GitHub Packages
# ├── Stop any existing target environment containers
# ├── Start target database container
# ├── Wait for database to be ready
# ├── Start target API container
# └── Health check target API
```

### Stage 6: Database Migration
```bash
./scripts/database/migrate.sh <target_env>

# What this script does:
# ├── Create backup of target database
# ├── Run Entity Framework migrations
# ├── Verify migration success
# └── Test API connectivity
```

### Stage 7: Health Check & Integration Tests
```bash
# Health check target environment
./scripts/monitoring/health-check.sh backend <target_env>

# Integration tests (unless SKIP_TESTS = true)
./scripts/monitoring/integration-test.sh <target_env>
```

### Stage 8: Approve Traffic Switch
```bash
# Manual approval required (unless AUTO_SWITCH_TRAFFIC = true)
# Manager/Lead clicks "Switch to <target_env>" in Jenkins UI

# If first deployment:
#   Prompt: "Go Live with <target_env>"
# If blue-green switch:
#   Prompt: "Switch traffic from <current_env> to <target_env>"
```

### Stage 9: Switch Traffic
```bash
./scripts/deployment/blue-green-switch.sh <target_env> api

# What this script does:
# ├── Backup current nginx config
# ├── Update nginx to route API traffic to target environment
# ├── Reload nginx configuration
# ├── Verify health checks pass
# └── Mark TRAFFIC_SWITCHED = true
```

### Post-Build: Automatic Rollback on Failure
```bash
# If pipeline fails AFTER traffic switch:
./scripts/deployment/blue-green-switch.sh <previous_env> api

# Restores traffic to previous environment
# Sends rollback notification
```

## 3. Frontend Deployment Flow

### Stage 1: Determine Target Environment
```bash
# Same logic as backend - detects current live environment
# and deploys to the opposite (idle) environment
```

### Stage 2: Build & Test
```bash
# Checkout staging branch from GitHub (rocsa65/client)
# Install dependencies: npm ci
# Unit tests: npm run test:unit (unless SKIP_TESTS = true)
# Integration tests: npm run test:integration
# UI/E2E tests: npm run test:e2e:headless
```

### Stage 3: Build & Push Docker Image
```bash
# Build Docker image with release number tag
docker build -t ghcr.io/rocsa65/myfinance-client:v20251111-044054-2 -f Dockerfile .
docker tag ghcr.io/rocsa65/myfinance-client:v20251111-044054-2 ghcr.io/rocsa65/myfinance-client:latest

# Push to GitHub Container Registry
docker push ghcr.io/rocsa65/myfinance-client:v20251111-044054-2
docker push ghcr.io/rocsa65/myfinance-client:latest
```

### Stage 4: Update Production Branch
```bash
# Merge staging → production
# Create release tag: frontend-v20251111-044054-2
# Push to GitHub
```

### Stage 5: Deploy to Target Environment
```bash
./scripts/deployment/deploy-frontend.sh <target_env> <release_number>

# What this script does:
# ├── Pull Docker image from GitHub Packages
# ├── Stop any existing target environment containers
# ├── Start target client container
# └── Health check target client
```

### Stage 6: Health Check & Integration Tests
```bash
# Health check target environment
./scripts/monitoring/health-check.sh frontend <target_env>

# Frontend integration tests (unless SKIP_TESTS = true)
./scripts/monitoring/integration-test-frontend.sh <target_env>
```

### Stage 7: Approve Traffic Switch
```bash
# Manual approval required (unless AUTO_SWITCH_TRAFFIC = true)
# Manager/Lead approves traffic switch in Jenkins UI
```

### Stage 8: Switch Traffic
```bash
./scripts/deployment/blue-green-switch.sh <target_env> client

# What this script does:
# ├── Backup current nginx config
# ├── Update nginx to route client traffic to target environment
# ├── Reload nginx configuration
# ├── Verify health checks pass
# └── Mark TRAFFIC_SWITCHED = true
```

### Post-Build: Automatic Rollback on Failure
```bash
# If pipeline fails AFTER traffic switch:
./scripts/deployment/blue-green-switch.sh <previous_env> client

# Restores traffic to previous environment
# Sends rollback notification via notify-rollback.sh
```

## 4. Key Jenkins Configuration

### Jenkins Jobs (Auto-created via init.groovy.d)
```groovy
# Location: jenkins/docker/init.groovy.d/03-jobs.groovy

MyFinance/
├── Backend-Release     # Uses: pipelines/backend-release.groovy
└── Frontend-Release    # Uses: pipelines/frontend-release.groovy
```

### Required Jenkins Credentials
```bash
# Credential ID: github-token
# Type: Username with password
# Username: <your-github-username>
# Password: <github-personal-access-token>
# Scopes needed: write:packages, read:packages
```

### Environment Variables
```bash
DOCKER_REGISTRY='ghcr.io/rocsa65'
GITHUB_ORG='rocsa65'
RELEASE_NUMBER=v<yyyyMMdd-HHmmss>-<build_number>
TARGET_ENV=blue|green  # Auto-detected
CURRENT_ENV=blue|green|none  # Auto-detected
```

## 5. Blue-Green Deployment Strategy

### How Target Environment is Determined
```bash
# Read nginx config: /var/jenkins_home/docker/nginx/blue-green.conf

# If blue is active (uncommented):
#   → Deploy to green
# If green is active (uncommented):
#   → Deploy to blue
# If neither is active:
#   → First deployment, deploy to green
```

### Traffic Switch Process
```bash
./scripts/deployment/blue-green-switch.sh <target_env> <component>

# Component can be: api, client, or both
# ├── Backup nginx config with timestamp
# ├── Comment out old environment
# ├── Uncomment new environment
# ├── Reload nginx (no downtime)
# └── Health check new environment
```

### Rollback Process
```bash
# Automatic rollback triggers if:
# 1. Pipeline fails AFTER traffic switch
# 2. Health checks fail 3 consecutive times
# 3. Manual emergency rollback initiated

# Rollback switches traffic back to previous environment
# Previous environment remains running during deployment
```

## 6. Monitoring & Notifications

### Health Check Endpoints
```bash
# Backend: http://myfinance-api-<env>:80/health
# Frontend: http://myfinance-client-<env>:80/

# Expected responses:
# - HTTP 200 OK
# - Response time < 2 seconds
```

### Notification Scripts
```bash
./scripts/monitoring/notify-failure.sh <component> <release_number>
./scripts/monitoring/notify-rollback.sh <env> <status>
```

## 7. Release Number Format

```bash
# Format: v<yyyyMMdd-HHmmss>-<jenkins_build_number>
# Example: v20251111-044054-2

# Components:
# v          - Version prefix
# 20251111   - Date (November 11, 2025)
# 044054     - Time (04:40:54 AM)
# 2          - Jenkins build number

# Generated by: generateReleaseNumber() function in Groovy pipelines
```