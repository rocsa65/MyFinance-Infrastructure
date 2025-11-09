# 🚀 Quick Reference - Blue-Green Deployment

## First Time Setup

```bash
# 1. Edit configuration
notepad environments/production/.env
# Update: DOCKER_REGISTRY, GITHUB_PACKAGES_USER, GITHUB_PACKAGES_TOKEN

# 2. Run initialization (Git Bash or WSL)
bash scripts/deployment/init-blue-green.sh

# 3. Deploy blue environment
bash scripts/deployment/deploy-backend.sh blue latest
bash scripts/deployment/deploy-frontend.sh blue latest
```

## Common Commands

### Deploy
```bash
# Deploy to blue
bash scripts/deployment/deploy-backend.sh blue <version>
bash scripts/deployment/deploy-frontend.sh blue <version>

# Deploy to green
bash scripts/deployment/deploy-backend.sh green <version>
bash scripts/deployment/deploy-frontend.sh green <version>
```

### Database
```bash
# Copy database from blue to green
bash scripts/database/replicate.sh blue green

# Run migrations
bash scripts/database/migrate.sh <blue|green>

# Backup database
docker cp myfinance-api-blue:/data/finance_blue.db backup/
```

### Health Checks
```bash
# Check system health
bash scripts/monitoring/health-check.sh system blue
bash scripts/monitoring/health-check.sh system green

# Quick health check
curl http://localhost:5001/health  # Blue API
curl http://localhost:5002/health  # Green API
```

### Traffic Control
```bash
# Switch to green
bash scripts/deployment/blue-green-switch.sh green

# Rollback to blue
bash scripts/deployment/rollback.sh blue

# Check current environment
cat current-environment.txt
```

### Container Management
```bash
# View running containers
docker ps | grep myfinance

# View logs
docker logs myfinance-api-blue
docker logs myfinance-api-green

# Restart container
docker restart myfinance-api-blue
```

## Access Points

| Service | Blue | Green |
|---------|------|-------|
| API | http://localhost:5001 | http://localhost:5002 |
| Client | http://localhost:3001 | http://localhost:3002 |
| Health | http://localhost:5001/health | http://localhost:5002/health |

## Monitoring

```bash
# Start monitoring stack
cd monitoring && docker-compose up -d

# Prometheus: http://localhost:9090
# Grafana: http://localhost:3003 (admin/admin123)
```

## Logs

```bash
cat logs/deployment.log      # Deployment history
cat logs/health-check.log    # Health check results
cat logs/replication.log     # Database replication
cat logs/migration.log       # Database migrations
```

## Troubleshooting

```bash
# Container won't start?
docker logs myfinance-api-blue

# Database missing?
docker exec myfinance-api-blue ls -la /data/

# Script permission denied?
chmod +x scripts/**/*.sh

# Can't connect?
docker network inspect myfinance-network
```

## File Locations

- **Config**: `environments/production/.env`
- **Logs**: `logs/`
- **Backups**: `backup/`
- **Current env**: `current-environment.txt`

## Blue-Green Workflow

```
1. Deploy to Green    → deploy-backend.sh green v1.2.3
2. Replicate DB       → replicate.sh blue green
3. Run Migrations     → migrate.sh green
4. Test Green         → health-check.sh system green
5. Switch Traffic     → blue-green-switch.sh green
6. Monitor            → Check logs for 10 min
7. Rollback if needed → rollback.sh blue
```
