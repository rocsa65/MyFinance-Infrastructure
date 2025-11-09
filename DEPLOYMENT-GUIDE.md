# MyFinance Deployment Guide

This guide provides step-by-step instructions to deploy and run the MyFinance application using the blue-green deployment infrastructure.

## Prerequisites

- Docker and Docker Compose installed
- Git repository cloned
- Ports 80, 443, 5001, 5002, 8081 available

## Deployment Steps

### Step 1: Start Nginx Reverse Proxy

Start nginx first - it will wait for backend containers to be deployed.

```bash
cd docker/nginx
docker-compose up -d
```

**Verify nginx is running:**
```bash
docker ps
```

You should see `myfinance-nginx-proxy` container running on ports 80 and 443.

**Note:** Nginx is configured to route to GREEN initially. It will return 502 errors until the first backend deployment completes.

### Step 2: Start Jenkins CI/CD Server

Jenkins automates the blue-green deployment process and will configure nginx during the first deployment.

```bash
cd jenkins/docker
docker-compose up -d
```

**Access Jenkins:**
- URL: http://localhost:8081
- Username: `admin`
- Password: `admin123`

**Verify Jenkins is ready:**
- Wait 30-60 seconds for Jenkins to initialize
- Check that jobs are auto-created: `Backend-Release` and `Frontend-Release`

### Step 3: Configure GitHub Token in Jenkins

The pipeline needs access to your GitHub repository.

1. Go to Jenkins → Manage Jenkins → Credentials
2. Verify `github-token` credential exists
3. If not, create it:
   - Kind: Secret text
   - Secret: Your GitHub personal access token
   - ID: `github-token`

### Step 4: Run First Deployment

From Jenkins UI, trigger a backend deployment:

1. Open `Backend-Release` job
2. Click "Build with Parameters"
3. Enter:
   - `TAG`: Version tag (e.g., `v1.0.1`)
   - `REPO_URL`: `https://github.com/rocsa65/MyFinance-Backend.git`
4. Click "Build"

**Pipeline Stages:**
1. **Checkout** - Clones backend repository
2. **Build & Test** - Runs npm install and tests
3. **Build Docker Image** - Creates tagged Docker image
4. **Detect Environment** - Detects first deployment (neither BLUE nor GREEN active)
5. **Deploy to Target** - Deploys to GREEN (default for first deployment)
6. **Health Check** - Verifies new deployment is healthy
7. **Approval** - Manual approval gate (click "Proceed" in Jenkins)
8. **Switch Traffic** - Updates nginx config (GREEN is already active for first deployment)
9. **Verify** - Final health check on GREEN environment

**For subsequent deployments:**
- Pipeline detects which environment is live (BLUE or GREEN)
- Deploys new version to the inactive environment
- After approval, switches traffic to the newly deployed version

**Note:** The first deployment will:
- Detect that GREEN is configured but no container exists
- Deploy backend to GREEN environment  
- GREEN will immediately serve traffic through nginx (no traffic switch needed)

### Step 5: Monitor Deployment

**Check container status:**
```bash
docker ps | grep myfinance-api
```

**Check nginx routing:**
```bash
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf | grep "server myfinance-api"
```

Active environment will be uncommented, inactive will have `#` prefix.

**Check application health:**
```bash
curl http://localhost/api/health
```

### Step 6: Rollback (if needed)

If the new deployment has issues, rollback by switching traffic back:

```bash
cd scripts/deployment
./rollback.sh
```

Or manually trigger traffic switch:
```bash
./blue-green-switch.sh blue   # Switch to BLUE
./blue-green-switch.sh green  # Switch to GREEN
```

## Architecture Overview

### Blue-Green Deployment

- **BLUE Environment**: `myfinance-api-blue` on port 5001
- **GREEN Environment**: `myfinance-api-green` on port 5002
- **Nginx**: Routes traffic to active environment
- **Zero Downtime**: New version deployed to inactive, then traffic switches

### Network Configuration

All containers run on `myfinance-network` (external network):
- Backend containers connect to this network
- Nginx connects to this network
- Allows nginx to route to backend containers by name

### Configuration Synchronization

**CRITICAL**: These files must stay synchronized with exact text patterns:

1. `docker/nginx/blue-green.conf` - Nginx upstream configuration
2. `scripts/deployment/blue-green-switch.sh` - Traffic switching script
3. `jenkins/pipelines/backend-release.groovy` - Pipeline environment detection
4. `jenkins/docker/init.groovy.d/03-jobs.groovy` - Auto-job creation

**Required text pattern:**
```
server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;
server myfinance-api-green:80 max_fails=1 fail_timeout=10s;
```

The health check parameters (`max_fails=1 fail_timeout=10s`) are required for:
- Nginx failover detection
- Sed pattern matching in switch script
- Environment detection in pipelines

## Troubleshooting

### Nginx not starting
- Check nginx config syntax: `docker exec myfinance-nginx-proxy nginx -t`
- Check logs: `docker logs myfinance-nginx-proxy`
- Verify network exists: `docker network ls | grep myfinance`

### Backend container not accessible
- Check container is running: `docker ps | grep myfinance-api`
- Check logs: `docker logs myfinance-api-green` or `docker logs myfinance-api-blue`
- Verify network connection: `docker network inspect myfinance-network`

### Traffic switching fails
- Verify nginx config file exists in container: `docker exec myfinance-nginx-proxy ls -la /etc/nginx/conf.d/`
- Check sed patterns match config text exactly
- Verify backup file is created: `ls -la docker/nginx/ | grep backup`

### Jenkins build fails
- Check Jenkins logs: `docker logs myfinance-jenkins`
- Verify github-token credential is configured
- Check Docker daemon is accessible from Jenkins container

## Maintenance

### Update Backend Code

Simply trigger a new Jenkins build with a new tag:
1. Push code changes to GitHub with new tag
2. Run Backend-Release job with new TAG
3. Pipeline automatically deploys to inactive environment
4. Approve traffic switch when ready

### View Nginx Logs

```bash
docker logs -f myfinance-nginx-proxy
```

### Clean Up Old Containers

```bash
# Stop and remove all MyFinance containers
docker ps -a | grep myfinance | awk '{print $1}' | xargs docker stop
docker ps -a | grep myfinance | awk '{print $1}' | xargs docker rm
```

### Backup Database

```bash
# Backup BLUE database
docker cp myfinance-api-blue:/app/finance_blue.db ./backup/finance_blue_$(date +%Y%m%d).db

# Backup GREEN database
docker cp myfinance-api-green:/app/finance_green.db ./backup/finance_green_$(date +%Y%m%d).db
```

## Next Steps

- Set up monitoring with Prometheus/Grafana (see `monitoring/` directory)
- Configure SSL certificates for HTTPS
- Deploy frontend application
- Set up automated testing in pipeline
- Configure database replication between blue and green
