# Script Execution Flow

## 1. Release Pipeline Trigger (Jenkins)
```bash
# Jenkins executes this automatically when pipeline is triggered:
/var/jenkins_home/pipelines/frontend-release.groovy
/var/jenkins_home/pipelines/backend-release.groovy
```

## 2. Backend Deployment Flow
```bash
# Step 1: Deploy backend to green environment
./scripts/deployment/deploy-backend.sh green v20251108-001

# What this script does:
# ├── Pull Docker image from GitHub Packages
# ├── Stop any existing green containers
# ├── Start green database container
# ├── Wait for database to be ready
# ├── Start green API container
# └── Health check green API

# Step 2: Database migration on green
./scripts/database/migrate.sh green

# What this script does:
# ├── Create backup of green database
# ├── Run Entity Framework migrations
# ├── Verify migration success
# └── Test API connectivity
```

## 3. Frontend Deployment Flow
```bash
# Step 3: Deploy frontend to green environment  
./scripts/deployment/deploy-frontend.sh green v20251108-001

# What this script does:
# ├── Pull Docker image from GitHub Packages
# ├── Stop any existing green containers
# ├── Start green client container
# └── Health check green client
```

## 4. Data Replication (if needed)
```bash
# Step 4: Replicate data from blue to green
./scripts/database/replicate.sh blue green

# What this script does:
# ├── Create dump of blue database
# ├── Stop green API temporarily
# ├── Drop and recreate green database
# ├── Restore blue data to green
# ├── Restart green API
# └── Verify data integrity
```

## 5. Traffic Switch
```bash
# Step 5: Switch traffic to green environment
./scripts/deployment/blue-green-switch.sh green

# What this script does:
# ├── Backup current nginx config
# ├── Update nginx to route to green
# ├── Reload nginx configuration
# ├── Verify health checks pass
# └── Update current environment file
```

## 6. Production Monitoring
```bash
# Step 6: Monitor production for 10 minutes
./scripts/monitoring/production-monitor.sh 600

# What this script does:
# ├── Run health checks every 30 seconds
# ├── Monitor response times
# ├── Track memory usage
# ├── Count consecutive failures
# ├── If 3 failures → AUTOMATIC ROLLBACK
# └── Log all monitoring data
```

## 7. Emergency Rollback (if needed)
```bash
# If monitoring detects issues:
./scripts/deployment/emergency-rollback.sh blue

# What this script does:
# ├── Immediately switch nginx back to blue
# ├── Reload nginx configuration
# ├── Verify blue environment health
# ├── Send critical notifications
# └── Log rollback event
```