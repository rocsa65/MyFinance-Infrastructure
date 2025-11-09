# Real-World Release Example

## Scenario: Release v20251108-001

### Step 1: Release Manager Action
**Location:** Jenkins Dashboard (http://localhost:8080)
**Action:** Click "Build with Parameters" on MyFinance release pipeline
**Parameters:**
- RELEASE_TYPE: "full" (both frontend and backend)
- SKIP_TESTS: false
- AUTO_DEPLOY: false (manual approval required)

### Step 2: Jenkins Pipeline Execution

#### Frontend Pipeline (Parallel)
```bash
# Jenkins executes automatically:
git clone https://github.com/rocsa65/client.git --branch staging
cd client
npm ci
npm run test:unit          # ✅ 15 tests pass
npm run test:integration   # ✅ 8 tests pass  
npm run test:e2e          # ✅ 12 tests pass

# Build and push Docker image
docker build -t ghcr.io/rocsa65/myfinance-client:v20251108-001 .
docker push ghcr.io/rocsa65/myfinance-client:v20251108-001

# Update production branch
git checkout production
git merge staging --no-ff -m "Frontend Release v20251108-001"
git tag -a "frontend-v20251108-001" -m "Frontend Release v20251108-001"
git push origin production --tags
```

#### Backend Pipeline (Parallel)
```bash
# Jenkins executes automatically:
git clone https://github.com/rocsa65/server.git --branch staging
cd server
dotnet restore
dotnet test MyFinance.UnitTests/     # ✅ 23 tests pass
dotnet test MyFinance.IntegrationTests/ # ✅ 12 tests pass

# Build and push Docker image
docker build -t ghcr.io/rocsa65/myfinance-server:v20251108-001 .
docker push ghcr.io/rocsa65/myfinance-server:v20251108-001

# Update production branch  
git checkout production
git merge staging --no-ff -m "Backend Release v20251108-001"
git tag -a "backend-v20251108-001" -m "Backend Release v20251108-001"
git push origin production --tags
```

### Step 3: Deployment to Green Environment

#### Current State Check
```bash
# Blue environment is currently active
$ cat current-environment.txt
blue

# Blue containers running:
$ docker ps | grep myfinance
myfinance-api-blue      ✅ Up 2 days
myfinance-client-blue   ✅ Up 2 days
myfinance-nginx-proxy   ✅ Up 2 days

# Note: SQLite databases are embedded in API containers
# Blue DB: /data/finance_blue.db (inside myfinance-api-blue)
# Green DB: /data/finance_green.db (inside myfinance-api-green)
```

#### Deploy Backend to Green
```bash
# Jenkins calls:
./scripts/deployment/deploy-backend.sh green v20251108-001

# Script output:
Deploying backend to green environment with release v20251108-001...
Pulling backend image: ghcr.io/rocsa65/myfinance-server:v20251108-001
✅ Image pulled successfully
Starting backend API in green environment...
Waiting for API to be ready...
Health check attempt 1/30 - Status: 200
✅ Backend deployed successfully to green environment
Database: /data/finance_green.db (SQLite)
```

#### Deploy Frontend to Green
```bash
# Jenkins calls:
./scripts/deployment/deploy-frontend.sh green v20251108-001

# Script output:
Deploying frontend to green environment with release v20251108-001...
Pulling frontend image: ghcr.io/rocsa65/myfinance-client:v20251108-001
✅ Image pulled successfully
Starting frontend in green environment...
Health check attempt 1/30 - Status: 200
✅ Frontend deployed successfully to green environment
```

#### Database Migration
```bash
# Jenkins calls:
./scripts/database/migrate.sh green

# Script output:
Running database migrations on green environment...
Creating database backup before migration...
✅ Backup created: pre-migration-green-20251108-143045.db
Running Entity Framework migrations...
✅ Database migrations completed successfully
✅ Database file exists: finance_green.db (size: 245760 bytes)
✅ API health check passed after migration
```

### Step 4: Manual Approval
**Jenkins:** Pipeline pauses and asks "Deploy to Production?"
**Release Manager:** Clicks "Deploy" button

### Step 5: Traffic Switch
```bash
# Jenkins calls:
./scripts/deployment/blue-green-switch.sh green

# Script output:
Switching traffic to green environment...
Backed up nginx configuration to blue-green.conf.backup.20251108-143052
Updating nginx to route traffic to green environment...
Reloading nginx configuration...
✅ nginx configuration reloaded successfully
Verifying traffic switch...
✅ Traffic successfully switched to green environment
API Health: 200
Client Health: 200
```

### Step 6: Production Monitoring
```bash
# Jenkins calls:
./scripts/monitoring/production-monitor.sh 600

# Script output:
Monitoring production environment (green) for 600 seconds...
Monitoring started at 2025-11-08 14:30:52
Will monitor until 2025-11-08 14:40:52

⏱️ Monitoring... 570 seconds remaining (Failures: 0/3)
✅ Health check passed at 14:31:22
📊 Performance metrics:
   - API response time: 0.125s
   - Client response time: 0.089s
   - API memory usage: 145MB / 512MB
   - Client memory usage: 67MB / 256MB

⏱️ Monitoring... 540 seconds remaining (Failures: 0/3)
✅ Health check passed at 14:31:52
... (continues for 10 minutes)

🎉 Production monitoring completed successfully!
Duration: 600 seconds
Total failures: 0
✅ Final health check passed
```

### Step 7: Success Notification
```bash
# Jenkins calls:
./scripts/monitoring/notify-release.sh success v20251108-001

# Output:
🎉 SUCCESS: Release v20251108-001 success
✅ Release v20251108-001 completed successfully at 2025-11-08 14:40:52
Notification completed - details saved to release-v20251108-001.json
```

### Final State
```bash
# New active environment
$ cat current-environment.txt
green

# Green containers now serving traffic:
$ docker ps | grep myfinance
myfinance-api-green     ✅ Up 10 minutes (ACTIVE) - SQLite: /data/finance_green.db
myfinance-client-green  ✅ Up 10 minutes (ACTIVE)
myfinance-api-blue      ✅ Up 2 days (STANDBY) - SQLite: /data/finance_blue.db
myfinance-client-blue   ✅ Up 2 days (STANDBY)
myfinance-nginx-proxy   ✅ Up 2 days (routing to GREEN)

# Users accessing http://localhost now get the new release! 🎉
```