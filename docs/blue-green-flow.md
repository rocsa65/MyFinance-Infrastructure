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
       ▼
┌─────────────────┐     ┌─────────────────┐
│ BLUE Environment│ ←───┤ GREEN Environment│
│ (ACTIVE)        │     │ (STANDBY)       │
│ • API :5001     │     │ • API :5002     │
│ • Client :3001  │     │ • Client :3002  │
│ • DB :5433      │     │ • DB :5434      │
└─────────────────┘     └─────────────────┘
```

## Step 1: Deploy to Green
```
Internet Traffic
       │
       ▼
┌─────────────────┐
│ nginx Proxy     │ ← Still routes to BLUE
│ (Port 80)       │
└─────────────────┘
       │
       ▼
┌─────────────────┐     ┌─────────────────┐
│ BLUE Environment│     │ GREEN Environment│
│ (ACTIVE)        │     │ (DEPLOYING...)  │ ← New release
│ • API :5001     │     │ • API :5002     │   being deployed
│ • Client :3001  │     │ • Client :3002  │
│ • DB :5433      │     │ • DB :5434      │
└─────────────────┘     └─────────────────┘
```

## Step 2: Test Green Environment
```
┌─────────────────┐
│ Health Checks   │ → Test GREEN directly
│ • API Health    │   (bypass nginx)
│ • DB Migration  │
│ • Integration   │
└─────────────────┘
```

## Step 3: Switch Traffic to Green
```
Internet Traffic
       │
       ▼
┌─────────────────┐
│ nginx Proxy     │ ← Routes 100% traffic to GREEN
│ (Port 80)       │
└─────────────────┘
       │
       ▼
┌─────────────────┐     ┌─────────────────┐
│ BLUE Environment│     │ GREEN Environment│
│ (STANDBY)       │     │ (ACTIVE)        │ ← New active
│ • API :5001     │     │ • API :5002     │
│ • Client :3001  │     │ • Client :3002  │
│ • DB :5433      │     │ • DB :5434      │
└─────────────────┘     └─────────────────┘
```

## Step 4: Monitor for 10 Minutes
```
┌─────────────────┐
│ Production      │
│ Monitor         │ → Continuous health checks
│ • Response time │   If ANY failure detected:
│ • Error rate    │   → INSTANT ROLLBACK to BLUE
│ • DB health     │
└─────────────────┘
```