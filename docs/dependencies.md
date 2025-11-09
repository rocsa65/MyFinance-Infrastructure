# Infrastructure Dependencies and File Relationships

## Core Configuration Files
```
environments/production/.env
├── Contains: DB credentials, Docker registry, URLs
├── Used by: All deployment scripts
└── Loaded by: scripts/deployment/load-env.sh

docker/blue-green/docker-compose.blue.yml
├── Defines: Blue environment containers
├── Uses: Environment variables from .env
└── Started by: deploy-backend.sh and deploy-frontend.sh

docker/blue-green/docker-compose.green.yml  
├── Defines: Green environment containers
├── Uses: Environment variables from .env
└── Started by: deploy-backend.sh and deploy-frontend.sh

docker/nginx/blue-green.conf
├── Defines: Traffic routing rules
├── Modified by: blue-green-switch.sh
└── Used by: nginx container
```

## Jenkins Pipeline Dependencies
```
jenkins/Jenkinsfile (Main Pipeline)
├── Calls: jenkins/pipelines/frontend-release.groovy
├── Calls: jenkins/pipelines/backend-release.groovy  
└── Uses: All deployment scripts

jenkins/docker/docker-compose.yml
├── Builds: Jenkins container with all tools
├── Mounts: Pipeline scripts and deployment scripts
└── Uses: jenkins/docker/Dockerfile

jenkins/docker/Dockerfile
├── Installs: Node.js, .NET SDK, Docker CLI
├── Installs: Jenkins plugins from plugins.txt
└── Copies: Initialization scripts
```

## Script Dependencies Chain
```
Any deployment script
├── sources: scripts/deployment/load-env.sh
│   └── loads: environments/{env}/.env
├── calls: docker-compose commands
│   └── uses: docker/blue-green/*.yml files
└── logs to: logs/ directory

Health check scripts
├── reads: Container status via Docker API
├── makes: HTTP requests to health endpoints
└── logs to: logs/health-check.log

Monitoring scripts  
├── calls: health-check.sh repeatedly
├── reads: current-environment.txt
├── modifies: nginx configuration if rollback needed
└── logs to: logs/monitoring.log
```

## Database Scripts Dependencies
```
scripts/database/migrate.sh
├── requires: API container running (SQLite embedded)
├── executes: dotnet ef database update inside container
├── creates: backup of SQLite .db file before migration
├── verifies: Database file exists and has size > 0
└── verifies: API health after migration

scripts/database/replicate.sh
├── requires: Both blue and green API containers running
├── creates: Copy of source SQLite database file
├── stops: Target API container (prevent database locks)
├── copies: SQLite .db file from source to target
├── restarts: Target API container
└── verifies: Database file size matches source
```

## Monitoring Stack Dependencies
```
monitoring/docker-compose.yml
├── starts: Prometheus, Grafana, Node Exporter
├── uses: monitoring/prometheus/prometheus.yml
├── mounts: monitoring/grafana/ dashboards
└── connects to: myfinance-network

monitoring/prometheus/prometheus.yml
├── scrapes: All application containers
├── uses: monitoring/prometheus/alert_rules.yml
└── connects to: Container health endpoints
```