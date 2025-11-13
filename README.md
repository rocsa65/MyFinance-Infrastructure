# MyFinance Infrastructure

This repository contains all infrastructure as code, deployment configurations, and automation scripts for the MyFinance application.

## 🏗️ Repository Structure

```
MyFinance-Infrastructure/
├── docker/                     # Docker configurations for deployment
│   ├── blue-green/             # Blue-green deployment configurations
│   └── nginx/                  # nginx proxy configurations
├── jenkins/                    # Jenkins CI/CD configurations
│   ├── pipelines/              # Pipeline scripts (backend-release, frontend-release)
│   └── docker/                 # Jenkins container setup
├── scripts/                    # Automation scripts
│   ├── database/               # Database backup/restore scripts
│   ├── deployment/             # Deployment automation (deploy-backend, deploy-frontend, blue-green-switch)
│   └── monitoring/             # Health check and monitoring scripts
├── docs/                       # Documentation files
│   ├── blue-green-flow.md      # Blue-green deployment flow diagrams
│   ├── script-flow.md          # Script execution flow
│   ├── database-architecture.md # Database architecture guide
│   └── database-diagram.md     # Database visual diagrams
├── DATABASE-QUICK-REF.md       # Database operations quick reference
├── DATABASE-IMPLEMENTATION.md  # Database implementation summary
├── DEPLOYMENT-GUIDE.md         # Complete deployment guide
└── QUICK-REFERENCE.md          # Command quick reference
```

## 🚀 Getting Started

### 📚 Documentation Guide

**Choose your path:**

1. **🆕 New to Blue-Green Deployment?**
   - Start here: [`DEPLOYMENT-GUIDE.md`](DEPLOYMENT-GUIDE.md)
   - Complete guide with Jenkins automation
   - Time: 15-20 minutes

2. **⚡ Quick Command Reference?**
   - Check: [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md)
   - All commands in one place
   - For experienced users

3. **🗄️ Database Operations?**
   - Quick ref: [`DATABASE-QUICK-REF.md`](DATABASE-QUICK-REF.md)
   - Architecture: [`docs/database-architecture.md`](docs/database-architecture.md)
   - Backup/restore procedures and troubleshooting

### Prerequisites

- Docker Desktop
- Jenkins (containerized)
- Git
- Node.js 18+ (for frontend)
- .NET 9 SDK (for backend)

### Quick Setup

1. **Create Docker network**
   ```bash
   docker network create myfinance-network
   ```

2. **Start Jenkins and Nginx infrastructure**
   ```bash
   cd jenkins/docker
   docker-compose up -d
   cd ../..
   ```

3. **Copy nginx configuration**
   ```bash
   docker cp docker/nginx/blue-green.conf myfinance-nginx-proxy:/etc/nginx/conf.d/default.conf
   docker exec myfinance-nginx-proxy nginx -s reload
   ```

4. **Access Jenkins**
   - URL: http://localhost:8081
   - Username: `admin`
   - Password: `admin123`

5. **Configure GitHub token in Jenkins**
   - Navigate to: Manage Jenkins → Credentials → System → Global credentials
   - Add credential with ID: `github-token`
   - Use your GitHub Personal Access Token with `write:packages` scope

6. **Deploy application**
   - Run Backend-Release job in Jenkins
   - Run Frontend-Release job in Jenkins
   - See [`DEPLOYMENT-GUIDE.md`](DEPLOYMENT-GUIDE.md) for detailed steps

## 🔄 Blue-Green Deployment

This infrastructure implements a blue-green deployment strategy with a **shared database architecture**:

- **Blue Environment**: One of two identical production environments
- **Green Environment**: The other production environment
- **nginx Proxy**: Routes traffic between blue and green environments
- **Shared Database**: Both environments use the same SQLite database (`myfinance.db`)
- **Zero Downtime**: Instant traffic switching with no data loss

### Key Features

- **Data Persistence**: Shared database ensures data survives all deployments
- **Instant Rollback**: Switch back to previous environment immediately
- **Backward Compatible Migrations**: Database changes support both environments
- **Automated Backups**: Scripts for database backup before deployments

### Deployment Process

1. Jenkins detects which environment is active
2. Deploy new version to inactive environment
3. Run health checks and integration tests
4. Database migrations applied automatically (if any)
5. Switch traffic to new environment via nginx
6. Monitor for issues
7. Previous environment kept as instant rollback option

## 📋 Pipeline Overview

### Frontend Pipeline
- Checkout staging branch from `rocsa65/client`
- Run tests (if enabled)
- Build Docker image
- Push to GitHub Container Registry (ghcr.io)
- Detect active environment
- Deploy to inactive environment
- Run health checks
- Switch traffic (if auto-switch enabled)
- Stop previous environment

### Backend Pipeline
- Checkout staging branch from `rocsa65/MyFinance`
- Run tests (if enabled)
- Build Docker image
- Push to GitHub Container Registry (ghcr.io)
- Detect active environment
- Deploy to inactive environment
- Database migrations run automatically on container start
- Run health checks
- Switch traffic (if auto-switch enabled)
- Stop previous environment

## 🗃️ Database Management

- **Database Type**: SQLite (file-based, embedded in API containers)
- **Shared Database**: Both blue and green environments use the same database file
- **Database File**: `/data/myfinance.db` (shared across both environments)
- **Volume**: `shared_api_data` (mounted by both blue and green containers)
- **Migration**: Automated through Entity Framework Core migrations
- **Data Persistence**: Data persists across all blue-green deployments
- **Backup**: Use provided scripts to backup before major deployments

**Important:** Since both environments share the same database, database migrations must be backward compatible to support rollback scenarios. See [`docs/database-architecture.md`](docs/database-architecture.md) for details.

## 📊 Monitoring & Health Checks

- **Health Endpoints**: `/health` for API health checks
- **Container Health**: Docker healthcheck in compose files
- **Nginx Status**: Traffic routing verification
- **Database Connectivity**: Verified during deployment
- **Automated Rollback**: On health check failures (if traffic already switched)
- **Manual Verification**: Integration tests via scripts

## 🔧 Configuration

All configuration is managed through:
- **Jenkins Environment Variables**: Set in pipeline `environment` blocks
- **Docker Compose Files**: Environment-specific settings in `docker/blue-green/`
- **Jenkins Credentials**: Secure secrets managed through Jenkins credentials store
- **Nginx Configuration**: `docker/nginx/blue-green.conf`

Key configuration values:
- `DOCKER_REGISTRY`: `ghcr.io/rocsa65` (GitHub Container Registry)
- `RELEASE_NUMBER`: Auto-generated by Jenkins (`vYYYYMMDD-HHMMSS-N`)
- `GITHUB_TOKEN`: Stored in Jenkins credentials as `github-token`
- `shared_api_data`: Docker volume for shared database

## 🛠️ Manual Operations

### Switch Traffic (Manual)
```bash
# Switch both API and client to green environment
./scripts/deployment/blue-green-switch.sh green both

# Switch only API
./scripts/deployment/blue-green-switch.sh green api

# Switch only client
./scripts/deployment/blue-green-switch.sh green client
```

### Rollback (Emergency)
```bash
# Rollback both services to blue environment
./scripts/deployment/blue-green-switch.sh blue both

# Rollback only API
./scripts/deployment/blue-green-switch.sh blue api

# Rollback only client
./scripts/deployment/blue-green-switch.sh blue client
```

### Database Operations
```bash
# Backup database before deployment
./scripts/database/backup-db.sh    # Linux/macOS
./scripts/database/backup-db.bat   # Windows

# Restore database if needed
./scripts/database/restore-db.sh <backup-file>    # Linux/macOS
./scripts/database/restore-db.bat <backup-file>   # Windows

# Manual backup (alternative)
docker cp myfinance-api-green:/data/myfinance.db backups/myfinance-$(date +%Y%m%d-%H%M%S).db
```

**Note**: Both blue and green environments share the same database (`myfinance.db`). See [`DATABASE-QUICK-REF.md`](DATABASE-QUICK-REF.md) for complete database operations reference.

## 📝 Additional Documentation

- **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** - Complete deployment guide with troubleshooting
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Command cheat sheet for daily operations
- **[DATABASE-QUICK-REF.md](DATABASE-QUICK-REF.md)** - Database operations reference
- **[DATABASE-IMPLEMENTATION.md](DATABASE-IMPLEMENTATION.md)** - Database architecture implementation
- **[docs/database-architecture.md](docs/database-architecture.md)** - Complete database architecture guide
- **[docs/database-diagram.md](docs/database-diagram.md)** - Visual database architecture diagrams
- **[docs/blue-green-flow.md](docs/blue-green-flow.md)** - Blue-green deployment flow diagrams
- **[docs/script-flow.md](docs/script-flow.md)** - Script execution flow documentation
- **[CHANGELOG.md](CHANGELOG.md)** - Infrastructure change log

## 🤝 Contributing

1. Create feature branch from `main`
2. Make infrastructure changes
3. Test in development environment
4. Create pull request
5. Review and merge to main

## � License

This infrastructure is part of the MyFinance project.