# MyFinance Deployment Guide

This guide provides complete instructions to deploy, run, and manage the MyFinance application using blue-green deployment infrastructure.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Fresh Installation](#fresh-installation)
3. [First Deployment](#first-deployment)
4. [Subsequent Deployments](#subsequent-deployments)
5. [Monitoring & Verification](#monitoring--verification)
6. [Rollback Procedures](#rollback-procedures)
7. [Clean Slate Reset](#clean-slate-reset)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Docker Desktop installed and running
- Git configured with GitHub credentials
- GitHub Personal Access Token (for pushing Docker images to ghcr.io)
- Ports available: 80, 443, 3001, 3002, 5001, 5002, 8081, 50000

## Fresh Installation

### Step 1: Clean Up (Optional)

If you have previous installations, clean up first:

```cmd
.\cleanup-all.bat
```

This removes all containers, images, volumes, and networks.

### Step 2: Create Docker Network

Create the external network that all containers will use:

```cmd
docker network create myfinance-network
```

### Step 3: Start Jenkins & Nginx

Jenkins and Nginx run together in the same Docker Compose stack:

```cmd
cd jenkins\docker
docker-compose up -d
```

**Wait 1-2 minutes** for Jenkins to initialize.

**Verify containers are running:**
```cmd
docker ps
```

You should see:
- `myfinance-jenkins` - Running on port 8081
- `myfinance-nginx-proxy` - Running on ports 80 and 443

### Step 4: Access Jenkins

- **URL:** http://localhost:8081
- **Username:** `admin`
- **Password:** `admin123`

**Verify Jenkins Setup:**
1. Check folder exists: `MyFinance`
2. Check jobs exist: `Backend-Release`, `Frontend-Release`
3. Check credentials exist: Navigate to Manage Jenkins → Credentials

### Step 5: Configure GitHub Token

The GitHub token must be configured for pushing Docker images to GitHub Container Registry.

1. Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. Look for credential with ID: `github-token`
3. If it doesn't exist, create it:
   - Click **Add Credentials**
   - Kind: **Username with password**
   - Username: Your GitHub username
   - Password: Your GitHub Personal Access Token (with `write:packages` scope)
   - ID: `github-token`
   - Description: `GitHub Container Registry Access`
   - Click **Create**

**Note:** The token needs `write:packages` permission to push Docker images to ghcr.io.

---

## First Deployment

### Backend Deployment (First Time)

1. Navigate to: **MyFinance** → **Backend-Release**
2. Click **"Build with Parameters"**
3. Configure parameters:
   - **RELEASE_NUMBER:** Leave empty (auto-generates timestamp-based version)
   - **SKIP_TESTS:** ☑️ Check (tests are mocked until you add real tests)
   - **SKIP_MIGRATION:** ☑️ Check (no migrations needed for first deploy)
   - **AUTO_SWITCH_TRAFFIC:** ☑️ Check (auto-switch for first deployment)
4. Click **"Build"**

**What Happens:**
- Checks out code from `staging` branch of `rocsa65/MyFinance` repository
- Runs .NET build
- Builds Docker image: `ghcr.io/rocsa65/myfinance-server:v20251110-HHMMSS-X`
- Pushes to GitHub Container Registry
- Detects no active environment → Deploys to **GREEN** (default)
- Updates production branch and creates release tag
- Health check verifies deployment
- Switches nginx traffic to GREEN
- GREEN becomes live

**Expected Result:**
- Container `myfinance-api-green` running on port 5002
- API accessible at: `http://localhost/health` → HTTP 200
- GREEN environment active

**Timeline:** 3-5 minutes

### Frontend Deployment (First Time)

1. Navigate to: **MyFinance** → **Frontend-Release**
2. Click **"Build with Parameters"**
3. Configure parameters:
   - **RELEASE_NUMBER:** Leave empty (auto-generates)
   - **SKIP_TESTS:** ☑️ Check (tests are mocked)
   - **AUTO_SWITCH_TRAFFIC:** ☑️ Check (auto-switch)
4. Click **"Build"**

**What Happens:**
- Checks out code from `staging` branch of `rocsa65/client` repository
- Runs npm install
- Builds Docker image: `ghcr.io/rocsa65/myfinance-client:v20251110-HHMMSS-X`
- Pushes to GitHub Container Registry
- Detects no active client → Deploys to **GREEN** (matches backend)
- Updates production branch
- Health check verifies deployment
- Switches nginx client traffic to GREEN
- GREEN becomes live

**Expected Result:**
- Container `myfinance-client-green` running on port 3002
- Client accessible at: `http://localhost/` (with Host: myfinance.local)
- GREEN environment active

**Timeline:** 3-5 minutes

---

## Subsequent Deployments

### Backend Deployment (Blue-Green Switch)

For second and subsequent deployments:

1. Navigate to: **MyFinance** → **Backend-Release**
2. Click **"Build with Parameters"**
3. Configure parameters:
   - **RELEASE_NUMBER:** Leave empty or specify version
   - **SKIP_TESTS:** ☐ Uncheck (run tests) or ☑️ Check (skip)
   - **SKIP_MIGRATION:** Configure based on your needs
   - **AUTO_SWITCH_TRAFFIC:** 
     - ☑️ Check for automatic switching
     - ☐ Uncheck for manual approval
4. Click **"Build"**

**What Happens:**
- Detects GREEN is live
- Deploys new version to **BLUE**
- Health checks verify BLUE is healthy
- If AUTO_SWITCH_TRAFFIC is unchecked:
  - Pipeline pauses at "Approve Traffic Switch"
  - Manager/admin reviews logs
  - Clicks **"Proceed"** to approve
- Switches traffic from GREEN to BLUE
- Stops GREEN containers (saves resources)
- BLUE becomes live, GREEN is now idle

**Next deployment will:**
- Detect BLUE is live
- Deploy to GREEN
- Switch back to GREEN
- This alternates continuously

### Frontend Deployment (Blue-Green Switch)

Same process as backend:
1. Pipeline detects which environment is live
2. Deploys to inactive environment
3. Switches traffic after approval
4. Stops previous environment

---

## Monitoring & Verification

### Check Running Containers

```cmd
docker ps
```

**Expected containers:**
- `myfinance-jenkins` - Always running
- `myfinance-nginx-proxy` - Always running
- `myfinance-api-blue` OR `myfinance-api-green` - One running (active environment)
- `myfinance-client-blue` OR `myfinance-client-green` - One running (active environment)

### Check Active Environment

**Check nginx configuration:**
```cmd
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf | grep "server myfinance-api"
```

Active environment will be **uncommented**, inactive will have `#` prefix.

### Test API Health

```cmd
curl http://localhost/health
```

**Expected:** HTTP 200 with health status

### Test Client

**From browser:**
```
http://localhost/
```

**From command line:**
```cmd
curl -H "Host: myfinance.local" http://localhost/
```

**Expected:** HTTP 200 with HTML content

### Check Logs

**Jenkins logs:**
```cmd
docker logs myfinance-jenkins
```

**Nginx logs:**
```cmd
docker logs myfinance-nginx-proxy
```

**Backend logs:**
```cmd
docker logs myfinance-api-green
docker logs myfinance-api-blue
```

**Frontend logs:**
```cmd
docker logs myfinance-client-green
docker logs myfinance-client-blue
```

---

## Rollback Procedures

### Understanding Rollback in Blue-Green Deployment

In blue-green deployment, **rollback is simply switching traffic back to the previous environment**. Since the old version remains running in the inactive environment after deployment, rollback is instant and safe.

### Automated Rollback (Built-in)

**The pipelines include automatic rollback** if deployment fails after traffic has been switched:

**How it works:**
1. Traffic is successfully switched to new environment (e.g., GREEN)
2. If any subsequent check fails or pipeline encounters an error
3. Pipeline automatically switches traffic back to previous environment (BLUE)
4. Sends rollback notification
5. Previous version continues serving traffic seamlessly

**When automatic rollback triggers:**
- ✅ Traffic was switched AND pipeline failed afterwards → **Auto-rollback to previous environment**
- ❌ Deployment failed BEFORE traffic switch → No rollback needed (old version still live)
- ❌ First deployment (no previous environment) → No rollback possible

**You'll see in the logs:**
```
🚨 AUTOMATIC ROLLBACK INITIATED 🚨
Rolling back to blue environment
✅ Rollback successful - traffic restored to blue
```

### Manual Rollback (If Needed)

If the new deployment has issues, switch traffic back to the previous environment:

```cmd
cd scripts\deployment

# Rollback API to BLUE environment
.\blue-green-switch.sh blue api

# Rollback client to BLUE environment
.\blue-green-switch.sh blue client

# Rollback both services together
.\blue-green-switch.sh blue both
```

**What this does:**
1. Starts the previous environment container if it was stopped
2. Verifies it's healthy
3. Switches nginx traffic routing
4. Stops the problematic new deployment

### Rollback via Jenkins Re-deployment

Deploy a previous release version:

1. Go to Jenkins → Backend-Release or Frontend-Release
2. Click "Build with Parameters"
3. Set RELEASE_NUMBER to previous version (e.g., v1.0.0)
4. Set AUTO_SWITCH_TRAFFIC to true
5. Click "Build"

**Note:** This rebuilds the old version rather than reusing the existing container.

### Emergency Manual Rollback

If automation fails, manually edit nginx config:

```cmd
# Edit the config file
notepad docker\nginx\blue-green.conf

# Copy to nginx container
docker cp docker\nginx\blue-green.conf myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf

# Reload nginx
docker exec myfinance-nginx-proxy nginx -s reload
```

---

## Clean Slate Reset

To completely remove all infrastructure and start fresh:

### Windows

```cmd
.\cleanup-all.bat
```

### Linux/Mac

```bash
./cleanup-all.sh
```

**This removes:**
- All MyFinance containers
- All Docker images (local and pulled)
- All volumes (⚠️ **data will be lost**)
- All networks

**Then follow Fresh Installation steps** (Steps 1-5 above)

---

## Troubleshooting

### Jenkins not accessible

**Symptoms:** Cannot reach http://localhost:8081

**Solutions:**
```cmd
# Check if Jenkins is running
docker ps | grep jenkins

# Check Jenkins logs
docker logs myfinance-jenkins

# Restart Jenkins stack
cd jenkins\docker
docker-compose restart
```

### Nginx returns 502 Bad Gateway

**Symptoms:** API or client returns 502

**Causes:**
- No environment is active (both blue and green commented out)
- Active environment container is stopped
- Backend/frontend container is not responding

**Solutions:**
```cmd
# Check which environment should be active
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf | grep "server myfinance"

# Check if containers are running
docker ps | grep myfinance

# Check nginx logs
docker logs myfinance-nginx-proxy

# Manually uncomment the active environment
notepad docker\nginx\blue-green.conf
docker cp docker\nginx\blue-green.conf myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
docker exec myfinance-nginx-proxy nginx -s reload
```

### Pipeline fails at "Build Docker Image"

**Symptoms:** Jenkins build fails with Docker error

**Causes:**
- Docker daemon not accessible from Jenkins container
- Dockerfile missing in repository
- Build context issues

**Solutions:**
```cmd
# Verify Docker socket is mounted
docker inspect myfinance-jenkins | grep "docker.sock"

# Check if Dockerfile exists in repo
# Backend: rocsa65/MyFinance repository needs Dockerfile at MyFinance.Api/Dockerfile
# Frontend: rocsa65/client repository needs Dockerfile at root

# Test Docker access from Jenkins
docker exec myfinance-jenkins docker ps
```

### Pipeline fails at "Push to Registry"

**Symptoms:** Push to ghcr.io fails with authentication error

**Causes:**
- GitHub token not configured
- Token lacks `write:packages` permission
- Token is expired

**Solutions:**
1. Go to Jenkins → Manage Jenkins → Credentials
2. Check `github-token` exists and is correct
3. Update token with fresh GitHub Personal Access Token:
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Generate new token with `write:packages` scope
   - Update Jenkins credential

### Health Check Fails

**Symptoms:** Deployment succeeds but health check returns 000 or non-200

**Causes:**
- Container name resolution failing
- Health endpoint doesn't exist
- Application not starting correctly

**Solutions:**
```cmd
# Test container directly
docker exec myfinance-jenkins curl http://myfinance-api-green:80/health
docker exec myfinance-jenkins curl http://myfinance-client-green:80/

# Check application logs
docker logs myfinance-api-green
docker logs myfinance-client-green

# Verify containers are on the same network
docker network inspect myfinance-network
```

### Traffic Switch Fails

**Symptoms:** Pipeline fails at "Switch Traffic to Target" stage

**Causes:**
- Sed patterns don't match nginx config
- Nginx config file not synced to container
- Nginx test fails

**Solutions:**
```cmd
# Check nginx config syntax
docker exec myfinance-nginx-proxy nginx -t

# Manually sync config
docker cp docker\nginx\blue-green.conf myfinance-jenkins:/var/jenkins_home/docker/nginx/blue-green.conf
docker cp docker\nginx\blue-green.conf myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf

# Reload nginx
docker exec myfinance-nginx-proxy nginx -s reload

# Check sed pattern matching
docker exec myfinance-jenkins grep "server myfinance-api" /var/jenkins_home/docker/nginx/blue-green.conf
```

### Database Migration Fails

**Symptoms:** SQLite database migration errors

**Solutions:**
```cmd
# Check database file exists
docker exec myfinance-api-green ls -la /data/

# Check database file permissions
docker exec myfinance-api-green stat /data/finance_green.db

# Manually run migrations
docker exec myfinance-api-green dotnet ef database update
```

### Port Conflicts

**Symptoms:** Docker Compose fails to start with port already allocated

**Solutions:**
```cmd
# Find what's using the port
netstat -ano | findstr :8081
netstat -ano | findstr :80

# Kill the process or change port in docker-compose.yml
```

### Network Issues

**Symptoms:** Containers can't communicate

**Solutions:**
```cmd
# Verify network exists
docker network ls | grep myfinance

# Recreate network
docker network rm myfinance-network
docker network create myfinance-network

# Restart all containers
cd jenkins\docker
docker-compose restart
```

---

## Architecture Overview

### Blue-Green Deployment Pattern

MyFinance uses blue-green deployment for zero-downtime releases:

- **BLUE Environment:** 
  - Backend: `myfinance-api-blue` (port 5001)
  - Frontend: `myfinance-client-blue` (port 3001)
  
- **GREEN Environment:**
  - Backend: `myfinance-api-green` (port 5002)
  - Frontend: `myfinance-client-green` (port 3002)

- **Nginx Proxy:** Routes traffic to active environment on ports 80/443

**Deployment Flow:**
1. Active environment (e.g., GREEN) serves production traffic
2. New version deploys to inactive environment (BLUE)
3. Health checks verify BLUE is working
4. Traffic switches from GREEN to BLUE
5. GREEN stops and becomes the new inactive environment
6. Next deployment goes to GREEN, and the cycle repeats

### Initial State

When infrastructure starts fresh:
- Both BLUE and GREEN are commented out in nginx config
- Nginx returns 502 until first deployment
- First deployment defaults to GREEN
- After approval, GREEN becomes live

### Network Architecture

All containers communicate via Docker network:

```
myfinance-network (bridge)
├── myfinance-jenkins (Jenkins + scripts)
├── myfinance-nginx-proxy (Nginx reverse proxy)
├── myfinance-api-blue (Backend - inactive)
├── myfinance-api-green (Backend - active)
├── myfinance-client-blue (Frontend - inactive)
└── myfinance-client-green (Frontend - active)
```

**Network must be external and created manually:**
```cmd
docker network create myfinance-network
```

### File Structure & Synchronization

**Critical files that must stay synchronized:**

1. **`docker/nginx/blue-green.conf`** - Nginx upstream configuration
   - Controls which environment receives traffic
   - Must use exact patterns for sed matching

2. **`scripts/deployment/blue-green-switch.sh`** - Traffic switching script
   - Uses sed to comment/uncomment upstreams
   - Copies config to nginx container
   - Verifies health before switching

3. **`jenkins/pipelines/backend-release.groovy`** - Backend CI/CD pipeline
   - Detects active environment by reading nginx config
   - Determines deployment target (opposite of active)

4. **`jenkins/pipelines/frontend-release.groovy`** - Frontend CI/CD pipeline
   - Same logic as backend for environment detection

**Required upstream pattern:**
```nginx
upstream myfinance_api {
    server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;
    # server myfinance-api-green:80 max_fails=1 fail_timeout=10s;
    server 127.0.0.1:65535 down;  # Placeholder
}
```

**Pattern requirements:**
- Exact spacing and formatting
- Health check parameters (`max_fails=1 fail_timeout=10s`)
- Placeholder server to prevent empty upstream errors

---

## Maintenance Tasks

### Update Application Code

**Backend:**
1. Push changes to `staging` branch in `rocsa65/MyFinance` repository
2. Trigger Backend-Release pipeline in Jenkins
3. Pipeline automatically builds, tests, and deploys

**Frontend:**
1. Push changes to `staging` branch in `rocsa65/client` repository
2. Trigger Frontend-Release pipeline in Jenkins
3. Pipeline automatically builds, tests, and deploys

### Database Backup

**Manual backup:**
```cmd
# Backup BLUE database
docker cp myfinance-api-blue:/data/finance_blue.db backup\finance_blue_%date:~-4,4%%date:~-10,2%%date:~-7,2%.db

# Backup GREEN database
docker cp myfinance-api-green:/data/finance_green.db backup\finance_green_%date:~-4,4%%date:~-10,2%%date:~-7,2%.db
```

**Restore backup:**
```cmd
docker cp backup\finance_green_20251110.db myfinance-api-green:/data/finance_green.db
docker restart myfinance-api-green
```

### Clean Up Old Images

```cmd
# Remove unused images
docker image prune -a

# Remove specific old versions
docker images | findstr myfinance-server
docker rmi ghcr.io/rocsa65/myfinance-server:old-version
```

### View Nginx Configuration

```cmd
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf
```

### Reload Nginx Configuration

After manual config edits:
```cmd
docker cp docker\nginx\blue-green.conf myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
docker exec myfinance-nginx-proxy nginx -s reload
```

---

## Security Considerations

### GitHub Token

- Store token securely in Jenkins credentials
- Use separate token per environment (dev/staging/prod)
- Rotate tokens periodically
- Limit scope to `write:packages` only

### Nginx Security Headers

Already configured in `blue-green.conf`:
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block

### SSL/TLS

To enable HTTPS:
1. Obtain SSL certificate
2. Update nginx configuration with certificate paths
3. Add SSL server block listening on port 443
4. Redirect HTTP to HTTPS

---

## Performance Tuning

### Nginx

Edit `docker/nginx/blue-green.conf`:
- Adjust worker processes
- Tune buffer sizes
- Configure caching headers
- Enable compression (gzip)

### Backend

- Adjust .NET runtime settings
- Configure connection pooling
- Tune SQLite pragmas
- Monitor resource usage

### Frontend

- Enable static asset caching
- Configure CDN (if applicable)
- Optimize bundle sizes
- Use compression

---

## Quick Reference

### Essential Commands

```cmd
# Start infrastructure
docker network create myfinance-network
cd jenkins\docker
docker-compose up -d

# Check status
docker ps
docker logs myfinance-jenkins
docker logs myfinance-nginx-proxy

# Test endpoints
curl http://localhost/health
curl -H "Host: myfinance.local" http://localhost/

# Switch traffic manually
cd scripts\deployment
.\blue-green-switch.sh green api
.\blue-green-switch.sh blue api

# Clean slate
.\cleanup-all.bat

# Backup databases
docker cp myfinance-api-green:/data/finance_green.db backup\
```

### Key URLs

- **Jenkins:** http://localhost:8081 (admin/admin123)
- **API Health:** http://localhost/health
- **Frontend:** http://localhost/ (Host: myfinance.local)
- **GitHub Packages:** https://github.com/rocsa65?tab=packages

### Pipeline Parameters

**Backend-Release:**
- RELEASE_NUMBER: Auto-generated or custom (e.g., v1.0.1)
- SKIP_TESTS: true/false
- SKIP_MIGRATION: true/false
- AUTO_SWITCH_TRAFFIC: true/false

**Frontend-Release:**
- RELEASE_NUMBER: Auto-generated or custom
- SKIP_TESTS: true/false
- AUTO_SWITCH_TRAFFIC: true/false

---

## Expected Timeline

- **Fresh Installation:** 10-15 minutes total
  - Network creation: < 1 minute
  - Jenkins startup: 1-2 minutes
  - Backend deployment: 3-5 minutes
  - Frontend deployment: 3-5 minutes

- **Subsequent Deployments:** 3-5 minutes each
  - Build & push: 2-3 minutes
  - Deploy & verify: 1-2 minutes

---

## Success Criteria

✅ Jenkins accessible at http://localhost:8081
✅ Both pipelines (Backend-Release, Frontend-Release) exist
✅ GitHub token credential configured
✅ Backend deployment completes successfully
✅ Frontend deployment completes successfully
✅ API responds with HTTP 200 at `/health`
✅ Client responds with HTTP 200 at `/`
✅ Traffic successfully switches between blue and green
✅ Inactive environment stops after traffic switch
✅ No errors in container logs
✅ Blue-green alternation works on subsequent deployments

---

## Support & Documentation

- **QUICK-REFERENCE.md:** Cheat sheet of common commands
- **docs/blue-green-flow.md:** Blue-green deployment flow diagrams
- **docs/script-flow.md:** Script execution flow and pipeline details

For issues, check the [Troubleshooting](#troubleshooting) section above.
