# Blue-Green Deployment Flow Diagram

## Current State: Blue is Live
```
Internet Traffic
       │
       ▼
┌─────────────────┐
│ nginx Proxy     │ ← Routes 100% traffic to BLUE
│ (Port 80)       │
└─────────────────┘
       │
       ├──────────────────┬──────────────────┐
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ BLUE (ACTIVE)│   │ GREEN (IDLE) │   │ Jenkins      │
│ • API :5001  │   │ • API :5002  │   │ :8081        │
│ • Client:3001│   │ • Client:3002│   └──────────────┘
│ • SQLite DB  │   │ • SQLite DB  │
└──────────────┘   └──────────────┘
```

## Step 1: Jenkins Pipeline Triggered
```
Developer → Push to GitHub (staging branch)
                │
                ▼
User → Jenkins UI → Click "Build with Parameters"
                │
                ▼
        ┌──────────────┐
        │ Jenkins      │
        │ Pipeline     │
        │ Triggered    │
        └──────────────┘
                │
                ├─→ Pull code from GitHub
                ├─→ Run tests (Unit, Integration, E2E)
                ├─→ Build Docker image
                └─→ Push to ghcr.io
```

## Step 2: Deploy to Green
```
Internet Traffic → nginx → BLUE (still active)
                            
┌──────────────┐   ┌──────────────┐   
│ BLUE (ACTIVE)│   │ GREEN        │   
│ • API :5001  │   │ (DEPLOYING...)│ ← Jenkins deploying
│ • Client:3001│   │ • API :5002  │   • Pull new image
│ • SQLite DB  │   │ • Client:3002│   • Start containers
└──────────────┘   │ • SQLite DB  │   • Run migrations
                   └──────────────┘
```

## Step 3: Health Checks & Testing
```
┌──────────────┐
│ Jenkins      │
│ Health Checks│ → Test GREEN directly
│              │   (container-to-container)
└──────────────┘
        │
        ├─→ curl http://myfinance-api-green:80/health
        ├─→ curl http://myfinance-client-green:80/
        ├─→ Integration tests
        └─→ Database verification
```

## Step 4: Switch Traffic to Green
```
Internet Traffic
       │
       ▼
┌─────────────────┐
│ nginx Proxy     │ ← Switch config: GREEN becomes active
│ (Port 80)       │   BLUE commented out
└─────────────────┘
       │
       ├──────────────────┬──────────────────┐
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ BLUE (IDLE)  │   │ GREEN (ACTIVE)│  │ Jenkins      │
│ • API :5001  │   │ • API :5002  │   │ Monitoring   │
│ • Client:3001│   │ • Client:3002│   └──────────────┘
│ • SQLite DB  │   │ • SQLite DB  │
│ (Stopped)    │   │ (Running)    │
└──────────────┘   └──────────────┘
```

## Step 5: Automatic Rollback on Failure
```
┌──────────────┐
│ Jenkins      │
│ Monitoring   │ → If pipeline fails AFTER traffic switch:
│              │   
└──────────────┘
        │
        ▼ (Failure detected)
        │
        ├─→ 1. Start BLUE container
        ├─→ 2. Wait for health check
        ├─→ 3. Switch nginx back to BLUE
        ├─→ 4. Stop GREEN container
        └─→ 5. Send rollback notification
```

## Infrastructure Components

### Containers
```
┌─────────────────────────────────────────┐
│ myfinance-network (Docker bridge)      │
├─────────────────────────────────────────┤
│ • myfinance-jenkins     :8081          │ ← CI/CD orchestration
│ • myfinance-nginx-proxy :80, :443      │ ← Traffic routing
│ • myfinance-api-blue    :5001          │ ← Backend (inactive)
│ • myfinance-api-green   :5002          │ ← Backend (active)
│ • myfinance-client-blue :3001          │ ← Frontend (inactive)
│ • myfinance-client-green:3002          │ ← Frontend (active)
└─────────────────────────────────────────┘
```

### Key Features

**Zero Downtime:**
- Old version (BLUE) keeps running until GREEN is verified
- Traffic switches instantly via nginx config change
- If GREEN fails, BLUE is still available for rollback

**Automated Testing:**
- Unit tests before build
- Integration tests after deployment
- Health checks before traffic switch

**Database Handling:**
- SQLite shared database across both environments
- Both blue and green containers use the same `/data/myfinance.db` file
- Database persists across all blue-green switches
- Migrations must be backward compatible for rollback support
- Automatic migrations on container startup
- See [Database Architecture](database-architecture.md) for details

**Service-Specific Switching:**
- Backend and frontend can be deployed independently
- `blue-green-switch.sh green api` - Switch only API
- `blue-green-switch.sh green client` - Switch only client  
- `blue-green-switch.sh green both` - Switch both services

## Rollback Scenarios

### Scenario 1: Deployment Fails Before Traffic Switch
```
GREEN deployment fails → Pipeline aborts
                      → BLUE stays active (no impact)
                      → No rollback needed
```

### Scenario 2: Traffic Switched, Then Failure
```
Traffic switched to GREEN → Pipeline fails
                         → AUTO-ROLLBACK triggered
                         → Switch back to BLUE
                         → Stop GREEN
                         → Production restored
```

### Scenario 3: Manual Rollback
```
User detects issue → Run: blue-green-switch.sh blue both
                  → Traffic switches to BLUE
                  → GREEN stopped
                  → Issue resolved
```

## Complete Jenkins Pipeline Flow

```
1. Code Push → GitHub (staging branch)
2. User → Jenkins UI → Build with Parameters
3. Checkout → Pull latest code from staging
4. Unit Tests → Run tests (fail = abort)
5. Integration Tests → Test application (fail = abort)
6. Build → Create Docker image
7. Push → Upload to ghcr.io
8. Deploy → Start GREEN containers
9. Migrate → Run database migrations (backend only)
10. Health Check → Verify GREEN is healthy
11. Switch Traffic → Update nginx config, reload
    └─→ env.TRAFFIC_SWITCHED = 'true'
12. Success → Pipeline complete
    OR
    Failure → Auto-rollback to BLUE

post {
    failure {
        if (TRAFFIC_SWITCHED) {
            → Run blue-green-switch.sh blue
            → Send notification
        }
    }
}
```

## Traffic Routing Details

### nginx Configuration States

**BLUE Active:**
```nginx
upstream myfinance_api {
    server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;
    # server myfinance-api-green:80 max_fails=1 fail_timeout=10s;
}
```

**GREEN Active:**
```nginx
upstream myfinance_api {
    # server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;
    server myfinance-api-green:80 max_fails=1 fail_timeout=10s;
}
```

**Traffic Switch Process:**
1. Script uses `sed` to comment/uncomment server lines
2. Config copied to nginx container
3. `nginx -t` validates syntax
4. `nginx -s reload` applies changes (zero downtime)

## Timeline Example

```
00:00 - Developer pushes code to GitHub staging branch
00:01 - User clicks "Build with Parameters" in Jenkins
00:02 - Jenkins pipeline starts
00:03 - Tests running (Unit + Integration)
00:06 - Building Docker image
00:08 - Pushing to ghcr.io
00:10 - Deploying to GREEN environment
00:12 - Running database migrations
00:13 - Health checks on GREEN
00:14 - Switching traffic to GREEN (BLUE stops)
00:15 - Pipeline complete ✅

Total Time: ~15 minutes
Manual Effort: Push code + Click "Build" button (~30 seconds)
Automatic Rollback: If any step fails after traffic switch
```