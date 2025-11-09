# MyFinance Infrastructure

This repository contains all infrastructure as code, deployment configurations, and automation scripts for the MyFinance application.

## 🏗️ Repository Structure

```
MyFinance-Infrastructure/
├── docker/                     # Docker configurations for deployment
│   ├── blue-green/             # Blue-green deployment configurations
│   ├── nginx/                  # nginx proxy configurations
│   └── production/             # Production Docker compose files
├── jenkins/                    # Jenkins CI/CD configurations
│   ├── pipelines/              # Pipeline scripts
│   ├── docker/                 # Jenkins container setup
│   └── shared-libraries/       # Reusable Jenkins libraries
├── scripts/                    # Automation scripts
│   ├── database/               # Database management scripts
│   ├── deployment/             # Deployment automation
│   └── monitoring/             # Health check and monitoring scripts
├── environments/               # Environment-specific configurations
│   ├── development/            # Development environment
│   ├── staging/               # Staging environment
│   └── production/            # Production environment
├── monitoring/                 # Monitoring and observability
│   ├── prometheus/            # Prometheus configuration
│   └── grafana/               # Grafana dashboards
└── terraform/                 # Infrastructure as Code (future)
    ├── modules/               # Reusable Terraform modules
    └── environments/          # Environment-specific Terraform configs
```

## 🚀 Getting Started

### Prerequisites

- Docker Desktop
- Jenkins (containerized)
- Git
- Node.js 18+ (for frontend)
- .NET 9 SDK (for backend)

### Quick Setup

1. **Clone the infrastructure repository**
   ```bash
   git clone https://github.com/rocsa65/MyFinance-Infrastructure.git
   cd MyFinance-Infrastructure
   ```

2. **Start Jenkins container**
   ```bash
   cd jenkins/docker
   docker-compose up -d
   ```

3. **Access Jenkins**
   - URL: http://localhost:8080
   - Initial admin password: Check `jenkins/docker/secrets/initialAdminPassword`

## 🔄 Blue-Green Deployment

This infrastructure supports blue-green deployment strategy:

- **Blue Environment**: Currently active production environment
- **Green Environment**: New deployment target for testing before switching
- **nginx Proxy**: Routes traffic between blue and green environments

### Deployment Process

1. Deploy to green environment
2. Run health checks and integration tests
3. Switch traffic from blue to green
4. Monitor for 10 minutes
5. If issues detected, rollback to blue

## 📋 Pipeline Overview

### Frontend Pipeline
- Pull from staging branch
- Run unit tests
- Run integration tests
- Run UI tests (Cypress)
- Build Docker image
- Push to GitHub Packages
- Deploy to green environment
- Run health checks
- Switch traffic if successful

### Backend Pipeline
- Pull from staging branch
- Run unit tests
- Run integration tests
- Run API health checks
- Build Docker image
- Push to GitHub Packages
- Deploy to green environment
- Run database migrations
- Run health checks
- Switch traffic if successful

## 🗃️ Database Management

- **All Environments**: SQLite (file-based, embedded in API containers)
- **Blue Environment**: `/data/finance_blue.db` (SQLite database file)
- **Green Environment**: `/data/finance_green.db` (SQLite database file)
- **Migration**: Automated through Entity Framework Core migrations
- **Replication**: File-based copying between blue and green environments
- **Backup**: SQLite database files are backed up before migrations and deployments

## 📊 Monitoring

- Health checks every 30 seconds
- Application metrics via Prometheus
- Visualization via Grafana
- Automated rollback on health check failures

## 🔧 Environment Variables

Key environment variables used across environments:

- `ENVIRONMENT`: development/staging/production
- `DB_CONNECTION_STRING`: Database connection
- `GITHUB_PACKAGES_TOKEN`: For Docker registry access
- `RELEASE_NUMBER`: Automatically generated release identifier

## 🛠️ Manual Operations

### Switch Traffic (Manual)
```bash
./scripts/deployment/blue-green-switch.sh green
```

### Rollback (Emergency)
```bash
./scripts/deployment/rollback.sh blue
```

### Database Backup
```bash
./scripts/database/backup.sh production
```

## 🤝 Contributing

1. Create feature branch from `main`
2. Make infrastructure changes
3. Test in development environment
4. Create pull request
5. Deploy to staging for testing
6. Merge to main after approval

## 📝 Release Notes

All infrastructure changes will be documented in [CHANGELOG.md](./CHANGELOG.md).