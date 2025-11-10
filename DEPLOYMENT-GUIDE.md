# MyFinance Deployment Guide

This guide provides step-by-step instructions to deploy and run the MyFinance application using the blue-green deployment infrastructure.

## Prerequisites

- Docker and Docker Compose installed
- Git repository cloned
- Ports 80, 443, 5001, 5002, 8081 available

## Deployment Steps

### Step 1: Create Docker Network

Create the external network that all containers will use:

```bash
docker network create myfinance-network
```

### Step 2: Start Jenkins CI/CD Server

Jenkins automates the blue-green deployment process and includes nginx in the same stack.

```bash
cd jenkins/docker
docker-compose up -d
```

**Access Jenkins:**
- URL: http://localhost:8081
- Username: `admin`
- Password: `admin123`

**Verify Jenkins and Nginx are running:**
```bash
docker ps
```

You should see:
- `myfinance-jenkins` container running on port 8081
- `myfinance-nginx-proxy` container running on ports 80 and 443

**Note:** Nginx starts with both BLUE and GREEN environments commented out (inactive). It will return 502 errors until the first backend deployment completes.

**Verify Jenkins is ready:**
- Wait 30-60 seconds for Jenkins to initialize
- Check that jobs are auto-created in the `MyFinance` folder: `Backend-Release` and `Frontend-Release`

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

1. Navigate to `MyFinance` folder
2. Open `Backend-Release` job
3. Click "Build with Parameters"
4. Enter:
   - `RELEASE_NUMBER`: Version number (e.g., `v1.0.1`) or leave empty to auto-generate
   - `SKIP_TESTS`: false (run tests)
   - `SKIP_MIGRATION`: false (run migrations)
   - `AUTO_SWITCH_TRAFFIC`: false (require manual approval)
5. Click "Build"

**Pipeline Stages:**
1. **Determine Target Environment** - Detects which environment is currently live
2. **Checkout Staging** - Clones from `staging` branch of `rocsa65/MyFinance` repository
3. **Build** - Runs dotnet build for .NET backend
4. **Test** - Runs dotnet test
5. **Build Docker Image** - Creates tagged Docker image for backend
6. **Push to Registry** - Pushes image to GitHub Container Registry (ghcr.io)
7. **Update Production Branch** - Merges staging to production branch and creates release tag
8. **Deploy to Target Environment** - Deploys to the inactive environment (GREEN for first deployment)
9. **Database Migration** - Runs database migrations on target environment
10. **Health Check Target** - Verifies new deployment is healthy
11. **Integration Test Target** - Runs integration tests against new deployment
12. **Approve Traffic Switch** - Manual approval gate (click "Proceed" in Jenkins)
13. **Switch Traffic to Target** - Updates nginx config to route traffic to new environment

**For subsequent deployments:**
- Pipeline detects which environment is live (BLUE or GREEN)
- Deploys new version to the inactive environment
- After approval, switches traffic to the newly deployed version
- Stops the now-inactive environment to save resources

**Note:** The first deployment will:
- Detect that neither BLUE nor GREEN is active (both commented out in nginx config)
- Deploy backend to GREEN environment (default for first deployment)
- After approval, uncomment GREEN in nginx config to start serving traffic
- GREEN becomes the live environment

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
- **Nginx**: Routes traffic to active environment (starts with both inactive)
- **Zero Downtime**: New version deployed to inactive, then traffic switches

### Initial State

When the infrastructure starts:
- Both BLUE and GREEN upstreams are commented out in nginx config
- Nginx returns 502 Bad Gateway until first deployment
- First deployment detects no active environment and defaults to GREEN
- After approval, GREEN is uncommented and becomes live

### Network Configuration

All containers run on `myfinance-network` (external network):
- Backend containers connect to this network
- Nginx connects to this network
- Jenkins connects to this network
- Allows nginx to route to backend containers by name

**Important:** The network must be created before starting Jenkins:
```bash
docker network create myfinance-network
```

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

**Initial state pattern (both commented):**
```
# server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;
# server myfinance-api-green:80 max_fails=1 fail_timeout=10s;
```

The health check parameters (`max_fails=1 fail_timeout=10s`) are required for:
- Nginx failover detection
- Sed pattern matching in switch script
- Environment detection in pipelines

## Troubleshooting

### Nginx not starting
- Nginx starts with Jenkins stack in `jenkins/docker`
- Check nginx config syntax: `docker exec myfinance-nginx-proxy nginx -t`
- Check logs: `docker logs myfinance-nginx-proxy`
- Verify network exists: `docker network ls | grep myfinance`
- If nginx failed to start, restart Jenkins stack: `cd jenkins/docker && docker-compose restart`

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

Simply trigger a new Jenkins build:
1. Push code changes to GitHub `staging` branch
2. Navigate to MyFinance folder → Backend-Release job
3. Click "Build with Parameters"
4. Enter RELEASE_NUMBER or leave empty for auto-generation
5. Pipeline automatically:
   - Builds and tests the code
   - Deploys to inactive environment
   - Merges to production branch
   - Creates release tag
6. Approve traffic switch when ready

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
# Backup BLUE database (SQLite)
docker cp myfinance-api-blue:/data/finance_blue.db ./backup/finance_blue_$(date +%Y%m%d).db

# Backup GREEN database (SQLite)
docker cp myfinance-api-green:/data/finance_green.db ./backup/finance_green_$(date +%Y%m%d).db
```

## Next Steps

- Set up monitoring with Prometheus/Grafana (see `monitoring/` directory)
- Configure SSL certificates for HTTPS
- Deploy frontend application
- Set up automated testing in pipeline
- Configure database replication between blue and green
