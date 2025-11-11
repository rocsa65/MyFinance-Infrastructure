# Blue-Green Deployment Docker Configuration

This directory contains Docker Compose configurations for blue-green deployment of the MyFinance application.

## Overview

The blue-green deployment strategy uses two identical production environments:
- **Blue**: One production environment (port 5001 for API, 3001 for client)
- **Green**: Second production environment (port 5002 for API, 3002 for client)

At any given time, one environment is active (serving production traffic) and the other is idle (ready for new deployment).

## Files

- `docker-compose.blue.yml`: Blue environment configuration (API on 5001, Client on 3001)
- `docker-compose.green.yml`: Green environment configuration (API on 5002, Client on 3002)

## Usage

### Deploy to Green Environment
```bash
# Pull and start green environment containers
cd docker/blue-green
docker-compose -f docker-compose.green.yml up -d
```

### Deploy to Blue Environment
```bash
# Pull and start blue environment containers
cd docker/blue-green
docker-compose -f docker-compose.blue.yml up -d
```

### Switch Traffic to Green
```bash
# Use the blue-green switch script to update nginx routing
cd ../../scripts/deployment
./blue-green-switch.sh green both
```

### Switch Traffic to Blue
```bash
cd ../../scripts/deployment
./blue-green-switch.sh blue both
```

### Rollback to Previous Environment
```bash
# If green is active and has issues, rollback to blue
cd ../../scripts/deployment
./blue-green-switch.sh blue both
```

## Environment Variables

Docker images are pulled from GitHub Container Registry:

- Images used:
  - `ghcr.io/rocsa65/myfinance-server:latest` (or specific version tag)
  - `ghcr.io/rocsa65/myfinance-client:latest` (or specific version tag)

## Networks

Both environments use the external Docker network `myfinance-network` which must be created before deployment:

```bash
docker network create myfinance-network
```

This allows:
- nginx proxy to route traffic to active environment
- Jenkins to perform health checks on containers
- Inter-container communication

## Automated Deployment via Jenkins

In practice, these Docker Compose files are used by Jenkins pipelines:
- `jenkins/pipelines/backend-release.groovy` - Deploys backend
- `jenkins/pipelines/frontend-release.groovy` - Deploys frontend

The pipelines automatically:
1. Detect which environment is currently active
2. Deploy to the inactive environment
3. Run health checks
4. Switch traffic via `blue-green-switch.sh`
5. Stop the previous environment to save resources

## Manual Operations

### View Running Containers
```bash
docker ps | grep myfinance
```

### Check Logs
```bash
# Blue environment
docker logs myfinance-api-blue
docker logs myfinance-client-blue

# Green environment
docker logs myfinance-api-green
docker logs myfinance-client-green
```

### Stop Environment
```bash
# Stop green environment
docker-compose -f docker-compose.green.yml down

# Stop blue environment
docker-compose -f docker-compose.blue.yml down
```

### Restart Environment
```bash
# Restart green environment
docker-compose -f docker-compose.green.yml restart

# Restart blue environment
docker-compose -f docker-compose.blue.yml restart
```

## Database Handling

Each environment has its own SQLite database:
- Blue: `/data/finance_blue.db` (inside `myfinance-api-blue` container)
- Green: `/data/finance_green.db` (inside `myfinance-api-green` container)

Databases are persisted in Docker volumes and remain independent between environments.

## Port Mapping

| Service | Blue (Direct) | Green (Direct) | Production (via nginx) |
|---------|---------------|----------------|------------------------|
| API | 5001 | 5002 | 80 (http://localhost/health) |
| Client | 3001 | 3002 | 80 (http://localhost/) |

**Note:** Production traffic always goes through nginx on port 80. Direct ports are for testing and debugging only.