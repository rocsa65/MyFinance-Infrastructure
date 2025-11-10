# 🚀 Quick Reference - Blue-Green Deployment

## Jenkins Deployment (Recommended)

```bash
# 1. Start Jenkins
cd jenkins\docker
docker-compose up -d

# 2. Access Jenkins: http://localhost:8081 (admin/admin)

# 3. Configure GitHub token in Jenkins UI
# Navigate to: Manage Jenkins → Credentials → Add github-token

# 4. Deploy via Jenkins
# Go to: MyFinance → Backend-Release → Build with Parameters
# Go to: MyFinance → Frontend-Release → Build with Parameters
```

## Manual Commands (Advanced Users)

### Quick Setup

```bash
# 1. Create Docker network
docker network create myfinance-network

# 2. Start Jenkins and nginx
cd jenkins\docker
docker-compose up -d
```

### Deploy (Via Scripts)

```bash
# Backend deployment (used by Jenkins)
bash scripts/deployment/deploy-backend.sh green <version>

# Frontend deployment (used by Jenkins)
bash scripts/deployment/deploy-frontend.sh green <version>
```

### Database

```bash
# Backup database
docker cp myfinance-api-blue:/data/finance_blue.db backup/
docker cp myfinance-api-green:/data/finance_green.db backup/

# View database
docker exec myfinance-api-green ls -la /data/
```

### Health Checks

```bash
# API health (through nginx)
curl http://localhost/health

# Client health (through nginx - requires Host header)
curl -H "Host: myfinance.local" http://localhost/

# Direct container health
docker exec myfinance-jenkins curl http://myfinance-api-green:80/health
docker exec myfinance-jenkins curl http://myfinance-client-green:80/
```

### Traffic Control

```bash
# Switch traffic (backend, frontend, or both)
cd scripts/deployment
./blue-green-switch.sh green api      # Switch API to GREEN
./blue-green-switch.sh blue api       # Switch API to BLUE
./blue-green-switch.sh green client   # Switch client to GREEN
./blue-green-switch.sh blue client    # Switch client to BLUE
./blue-green-switch.sh green both     # Switch both to GREEN
```

## Rollback

```bash
# Automatic rollback happens in Jenkins if deployment fails after traffic switch

# Manual rollback - switch traffic to previous environment
cd scripts/deployment
./blue-green-switch.sh blue api      # Rollback API to BLUE
./blue-green-switch.sh blue client   # Rollback client to BLUE
./blue-green-switch.sh blue both     # Rollback both to BLUE
```

## Access Points

| Service | Production (nginx) | Blue (direct) | Green (direct) |
|---------|-------------------|---------------|----------------|
| API | http://localhost/health | http://localhost:5001 | http://localhost:5002 |
| Client | http://localhost/ | http://localhost:3001 | http://localhost:3002 |
| Jenkins | http://localhost:8081 | - | - |

**Note:** Production traffic goes through nginx on port 80. Direct ports are for testing only.

### Container Management

```bash
# View running containers
docker ps | grep myfinance

# View logs
docker logs myfinance-jenkins
docker logs myfinance-nginx-proxy
docker logs myfinance-api-blue
docker logs myfinance-api-green
docker logs myfinance-client-blue
docker logs myfinance-client-green

# Restart container
docker restart myfinance-api-green
docker restart myfinance-client-green

# Check which environment is active
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf | grep "server myfinance"
```

## Jenkins Operations

```bash
# Start/Stop Jenkins
cd jenkins\docker
docker-compose up -d
docker-compose down

# View Jenkins logs
docker logs myfinance-jenkins

# Access Jenkins container
docker exec -it myfinance-jenkins bash

# Update pipeline (after editing .groovy files)
# Pipelines are stored in /var/jenkins_home/pipelines/ inside container
docker cp jenkins\pipelines\backend-release.groovy myfinance-jenkins:/var/jenkins_home/pipelines/
docker cp jenkins\pipelines\frontend-release.groovy myfinance-jenkins:/var/jenkins_home/pipelines/
```

## Logs

```bash
# Jenkins build logs
# View in Jenkins UI: Build → Console Output

# Container logs
docker logs myfinance-jenkins
docker logs myfinance-nginx-proxy
docker logs myfinance-api-green
docker logs myfinance-client-green
```

## Troubleshooting

```bash
# Jenkins won't start?
docker logs myfinance-jenkins
cd jenkins\docker
docker-compose restart

# Container won't start?
docker logs myfinance-api-green

# Database missing?
docker exec myfinance-api-green ls -la /data/

# Can't connect to containers?
docker network inspect myfinance-network

# Nginx returns 502?
docker logs myfinance-nginx-proxy
docker exec myfinance-nginx-proxy cat /etc/nginx/conf.d/default.conf

# Health checks failing?
# Check if using container names instead of localhost
docker exec myfinance-jenkins curl http://myfinance-api-green:80/health

# Pipeline fails?
# Check Jenkins Console Output for detailed error messages
```

## File Locations

- **Jenkins pipelines**: `jenkins/pipelines/`
- **Nginx config**: `docker/nginx/blue-green.conf`
- **Docker compose**: `jenkins/docker/docker-compose.yml`
- **Deployment scripts**: `scripts/deployment/`
- **Database backups**: `backup/`

## Blue-Green Workflow (Jenkins)

```
1. Push code to staging branch (GitHub)
2. Go to Jenkins → MyFinance → Backend-Release (or Frontend-Release)
3. Click "Build with Parameters"
4. Jenkins automatically:
   - Pulls code
   - Runs tests
   - Builds Docker image
   - Pushes to GitHub Packages
   - Deploys to GREEN
   - Runs migrations (backend only)
   - Performs health checks
   - Switches traffic to GREEN
   - Automatic rollback on failure
5. Monitor logs in Jenkins Console Output
```

## Clean Slate Reset

```bash
# Remove everything and start fresh
.\cleanup-all.bat   # Windows
./cleanup-all.sh    # Linux/Mac

# Then follow DEPLOYMENT-GUIDE.md Fresh Installation steps
```
