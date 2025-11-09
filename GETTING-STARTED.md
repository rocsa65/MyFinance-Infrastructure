# 🚀 Getting Started with MyFinance Blue-Green Deployment

## 📋 Prerequisites

Before you start, make sure you have:

- ✅ Docker Desktop installed and running
- ✅ Git Bash or WSL (for running bash scripts on Windows)
- ✅ MyFinance Docker images are available:
  - **Public packages** (ghcr.io/rocsa65): No authentication needed for deployment ✨
  - **Private packages**: GitHub Personal Access Token required

**Note:** Authentication is only required for **pushing** images (building releases). Deploying from public packages doesn't need credentials.

## 🎯 Quick Start Guide

### Step 1: Configure Environment Variables

1. **Edit the environment file:**
   ```bash
   # Navigate to your infrastructure repository root
   cd MyFinance-Infrastructure
   notepad environments/production/.env
   ```

2. **Update these values:**
   ```properties
   # GitHub Packages Registry
   DOCKER_REGISTRY=ghcr.io/rocsa65
   
   # Only required for PUSHING images (building releases)
   # Leave empty if you're only deploying from public packages
   GITHUB_PACKAGES_USER=rocsa65
   GITHUB_PACKAGES_TOKEN=your_github_token_here
   
   # Release versions (optional, defaults to 'latest')
   BLUE_RELEASE_NUMBER=latest
   GREEN_RELEASE_NUMBER=latest
   ```

3. **Save the file**

   **Notes:**
   - **Deploying only?** Leave `GITHUB_PACKAGES_TOKEN` empty if packages are public
   - **Building & pushing?** You need a GitHub PAT with `write:packages` permission
   - **Forking?** Change `rocsa65` to your GitHub username

### Step 2: Run Initial Setup

Open **Git Bash** (or WSL) in your infrastructure repository root and run:

```bash
# Navigate to your infrastructure repository root
cd MyFinance-Infrastructure
bash scripts/deployment/init-blue-green.sh
```

This will:
- ✅ Create required directories (`logs`, `backup`)
- ✅ Create Docker network (`myfinance-network`)
- ✅ Check for required Docker images
- ✅ Initialize environment tracking

### Step 3: Deploy Blue Environment (Initial Production)

```bash
# Deploy backend
cd scripts/deployment
bash deploy-backend.sh blue latest

# Deploy frontend
bash deploy-frontend.sh blue latest
```

**What happens:**
- Downloads the latest images from your registry
- Starts API container with SQLite database at `/data/finance_blue.db`
- Starts client container
- Runs health checks
- SQLite database is created automatically on first API call

### Step 4: Verify Deployment

```bash
# Check container status
docker ps | grep myfinance

# You should see:
# myfinance-api-blue
# myfinance-client-blue

# Check health
cd ../monitoring
bash health-check.sh system blue
```

**Access your application:**
- API (Blue): http://localhost:5001/health
- Client (Blue): http://localhost:3001

### Step 5: Test Database

```bash
# Check if SQLite database was created
docker exec myfinance-api-blue ls -lh /data/

# You should see: finance_blue.db
```

## 🔄 Blue-Green Deployment Workflow

### Deploy New Version to Green

1. **Deploy new release to green environment:**
   ```bash
   cd scripts/deployment
   
   # Deploy backend
   bash deploy-backend.sh green v20251109-001
   
   # Deploy frontend
   bash deploy-frontend.sh green v20251109-001
   ```

2. **Replicate database from blue to green:**
   ```bash
   cd ../database
   bash replicate.sh blue green
   ```
   
   This copies the SQLite database file from blue to green.

3. **Run migrations on green (if needed):**
   ```bash
   bash migrate.sh green
   ```

4. **Test green environment:**
   - Green API: http://localhost:5002/health
   - Green Client: http://localhost:3002

5. **If tests pass, switch traffic:**
   ```bash
   cd ../deployment
   bash blue-green-switch.sh green
   ```
   
   ⚠️ **Note:** This requires nginx to be configured. See nginx setup below.

### Rollback if Needed

```bash
cd scripts/deployment
bash rollback.sh blue
```

This immediately switches traffic back to blue environment.

## 🌐 Setting Up nginx (Optional but Recommended)

For production traffic switching, you need nginx configured:

1. **Check if nginx config exists:**
   ```bash
   ls docker/nginx/blue-green.conf
   ```

2. **Start nginx proxy:**
   ```bash
   cd docker/nginx
   docker-compose up -d
   ```

3. **Access through nginx:**
   - Production: http://localhost (routes to active environment)

## 📊 Monitoring

### Check System Health

```bash
cd scripts/monitoring
bash health-check.sh system blue   # Check blue environment
bash health-check.sh system green  # Check green environment
```

### View Logs

```bash
# API logs
docker logs myfinance-api-blue
docker logs myfinance-api-green

# Client logs  
docker logs myfinance-client-blue
docker logs myfinance-client-green

# Deployment logs
cat logs/deployment.log

# Health check logs
cat logs/health-check.log
```

### Start Monitoring Stack (Prometheus + Grafana)

```bash
cd monitoring
docker-compose up -d

# Access dashboards:
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3003 (user: admin, pass: admin123)
```

## 🗄️ Database Operations

### Backup Database

```bash
# Backup blue database
docker cp myfinance-api-blue:/data/finance_blue.db backup/finance_blue_$(date +%Y%m%d).db

# Backup green database
docker cp myfinance-api-green:/data/finance_green.db backup/finance_green_$(date +%Y%m%d).db
```

### Restore Database

```bash
# Restore to blue
docker cp backup/finance_blue_20251109.db myfinance-api-blue:/data/finance_blue.db
docker restart myfinance-api-blue

# Restore to green
docker cp backup/finance_green_20251109.db myfinance-api-green:/data/finance_green.db
docker restart myfinance-api-green
```

### View Database

```bash
# Copy database locally
docker cp myfinance-api-blue:/data/finance_blue.db ./finance_blue.db

# Open with SQLite browser or command line
sqlite3 finance_blue.db
sqlite> .tables
sqlite> SELECT * FROM Accounts;
sqlite> .quit
```

## 🐛 Troubleshooting

### Container won't start

```bash
# Check logs
docker logs myfinance-api-blue

# Common issues:
# - Image not found: Check DOCKER_REGISTRY in .env
# - Port conflict: Check if port 5001/3001 is in use
# - Network issue: Ensure myfinance-network exists
```

### Health check fails

```bash
# Test health endpoint directly
curl http://localhost:5001/health

# Check if container is running
docker ps | grep myfinance-api-blue

# Restart container
docker restart myfinance-api-blue
```

### Database not created

The SQLite database is created automatically when the API starts. If it's not there:

```bash
# Check API logs for errors
docker logs myfinance-api-blue

# Verify volume is mounted
docker inspect myfinance-api-blue | grep Mounts -A 10

# Trigger database creation by calling an API endpoint
curl http://localhost:5001/api/accounts
```

### "Permission denied" when running scripts

On Windows with Git Bash:

```bash
# Make scripts executable
chmod +x scripts/deployment/*.sh
chmod +x scripts/database/*.sh
chmod +x scripts/monitoring/*.sh
```

## 📁 Important Files and Directories

```
MyFinance-Infrastructure/
├── environments/production/.env    # Configuration (EDIT THIS)
├── scripts/deployment/
│   ├── init-blue-green.sh         # Run this first
│   ├── deploy-backend.sh          # Deploy API
│   ├── deploy-frontend.sh         # Deploy client
│   ├── blue-green-switch.sh       # Switch traffic
│   └── rollback.sh                # Emergency rollback
├── scripts/database/
│   ├── replicate.sh               # Copy database
│   └── migrate.sh                 # Run migrations
├── scripts/monitoring/
│   └── health-check.sh            # Health checks
├── logs/                          # Created automatically
│   ├── deployment.log
│   ├── health-check.log
│   └── replication.log
└── backup/                        # Created automatically
    └── *.db files
```

## 🎓 Typical Workflow Example

```bash
# 1. Initial Setup (once)
bash scripts/deployment/init-blue-green.sh

# 2. Deploy blue environment (first time)
bash scripts/deployment/deploy-backend.sh blue latest
bash scripts/deployment/deploy-frontend.sh blue latest

# 3. Verify it works
curl http://localhost:5001/health
curl http://localhost:3001

# 4. Deploy new version to green
bash scripts/deployment/deploy-backend.sh green v20251109-001
bash scripts/deployment/deploy-frontend.sh green v20251109-001

# 5. Copy data from blue to green
bash scripts/database/replicate.sh blue green

# 6. Test green environment
curl http://localhost:5002/health
curl http://localhost:3002

# 7. Switch traffic to green (if nginx is configured)
bash scripts/deployment/blue-green-switch.sh green

# 8. Monitor for issues
bash scripts/monitoring/health-check.sh system green

# 9. If problems, rollback
bash scripts/deployment/rollback.sh blue
```

## ✅ Next Steps

1. **Edit** `environments/production/.env` with your settings
2. **Run** `init-blue-green.sh` to set up infrastructure
3. **Deploy** to blue environment
4. **Test** that everything works
5. **Practice** deploying to green and switching
6. **Set up** nginx for production traffic switching
7. **Configure** CI/CD (Jenkins) for automated releases

## 📚 Additional Resources

- Full workflow: `docs/blue-green-flow.md`
- Release example: `docs/release-example.md`
- Script dependencies: `docs/dependencies.md`
- CI/CD setup: `jenkins/README.md`

## 💡 Tips

- Always test in green before switching traffic
- Keep blue environment running for quick rollback
- Replicate database before deploying new versions
- Monitor for at least 10 minutes after switching
- Keep backups of your SQLite databases
- Use specific version tags instead of 'latest' in production

## 🆘 Need Help?

Check the logs:
```bash
cat logs/deployment.log
cat logs/health-check.log
cat logs/replication.log
```

Verify containers:
```bash
docker ps
docker logs <container-name>
```

Check environment:
```bash
cat current-environment.txt
cat environments/production/.env
```
