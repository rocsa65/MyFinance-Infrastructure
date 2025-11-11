# Script Execution Flow

## Overview
The MyFinance deployment system provides three entry points in Jenkins:

1. **MyFinance/Backend-Release** - Deploy backend only
2. **MyFinance/Frontend-Release** - Deploy frontend only
3. **MyFinance/Full-Release** - Orchestrator with choice: frontend, backend, or both

## 1. Release Pipeline Trigger (Jenkins)

### Option A: Individual Component Release
```bash
# Backend only:
/var/jenkins_home/pipelines/backend-release.groovy

# Frontend only:
/var/jenkins_home/pipelines/frontend-release.groovy
```

### Option B: Orchestrated Release (Full-Release Job)
```bash
# Main orchestrator with parameters:
/var/jenkins_home/Jenkinsfile

# Parameters:
# - RELEASE_TYPE: frontend | backend | full
# - SKIP_TESTS: false (default)
# - AUTO_DEPLOY: false (default)

# What happens:
# ├── If RELEASE_TYPE = 'frontend' → Triggers Frontend-Release job
# ├── If RELEASE_TYPE = 'backend' → Triggers Backend-Release job
# └── If RELEASE_TYPE = 'full' → Triggers both + full system tests
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
```

## 4. Full Release Flow (Orchestrator)

When using **MyFinance/Full-Release** job with `RELEASE_TYPE = 'full'`:

### Stage 1: Setup
```bash
# Generate unique release number: v20251111-044054-2
# Display release type and number
```

### Stage 2: Frontend Release
```bash
# Triggers MyFinance/Frontend-Release job
# Passes RELEASE_NUMBER and SKIP_TESTS parameters
# Waits for completion
```

### Stage 3: Backend Release
```bash
# Triggers MyFinance/Backend-Release job
# Passes RELEASE_NUMBER and SKIP_TESTS parameters
# Waits for completion
```

### Stage 4: Full System Test
```bash
# Only runs for 'full' deployments
./scripts/monitoring/system-health-check.sh green

# Tests entire system integration
# Verifies frontend-backend communication
```

### Stage 5: Production Deployment
```bash
# If AUTO_DEPLOY = true → proceeds automatically
# Otherwise → waits for manual approval

./scripts/deployment/blue-green-switch.sh green

# Switches both frontend and backend traffic
```

### Stage 6: Production Monitoring
```bash
./scripts/monitoring/production-monitor.sh 600

# Monitors for 10 minutes (600 seconds)
# Runs health checks every 30 seconds
# Triggers rollback on 3 consecutive failures
```

### Stage 7: Post-Deployment Verification
```bash
./scripts/monitoring/post-deployment-check.sh

# Final verification checks
# Send success notification
./scripts/monitoring/notify-release.sh success v20251111-044054-2
```

### Post-Build: Emergency Rollback
```bash
# On failure:
./scripts/deployment/emergency-rollback.sh
./scripts/monitoring/notify-release.sh failure v20251111-044054-2

# On success:
./scripts/deployment/cleanup.sh
```

## 5. Key Jenkins Configuration

### Jenkins Jobs (Auto-created via init.groovy.d)
```groovy
# Location: jenkins/docker/init.groovy.d/03-jobs.groovy

MyFinance/
├── Backend-Release     # Uses: pipelines/backend-release.groovy
├── Frontend-Release    # Uses: pipelines/frontend-release.groovy
└── Full-Release        # Uses: Jenkinsfile (orchestrator)
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

## 6. Blue-Green Deployment Strategy

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

## 7. Monitoring & Notifications

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
./scripts/monitoring/notify-release.sh <status> <release_number>
./scripts/monitoring/notify-failure.sh <component> <release_number>
./scripts/monitoring/notify-rollback.sh <env> <status>
```

## 8. Release Number Format

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