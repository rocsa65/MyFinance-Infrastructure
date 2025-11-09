# 🚀 Jenkins Setup Guide for MyFinance Blue-Green Deployment

## 📋 What Jenkins Does

Jenkins **automates** the entire deployment process:
1. ✅ Pulls code from GitHub
2. ✅ Runs tests (unit, integration, E2E)
3. ✅ Builds Docker images
4. ✅ Pushes images to GitHub Packages
5. ✅ Deploys to green environment
6. ✅ Runs migrations
7. ✅ Switches traffic (with approval)
8. ✅ Monitors production
9. ✅ Rolls back if problems detected

**Without Jenkins:** You run all scripts manually
**With Jenkins:** Click one button, Jenkins does everything

---

## 🎯 Quick Start (15 minutes)

### Step 1: Start Jenkins Container

Navigate to the Jenkins Docker directory in your infrastructure folder:

```powershell
cd jenkins\docker
docker-compose up -d
```

Wait 1-2 minutes for Jenkins to start.

### Step 2: Access Jenkins

Open browser: **http://localhost:8081**

**Login with default credentials:**
- Username: `admin`
- Password: `admin123`

**Important:** Change the password after first login!
1. Click on **"admin"** (top right) → **Configure**
2. Scroll to **"Password"** section
3. Enter new password
4. Click **"Save"**

---

## ⚙️ Configure Jenkins (10 minutes)

### Step 1: Add GitHub Credentials (Required for CI/CD)

**Important:** GitHub credentials are needed to:
- ✅ **Push Docker images** to GitHub Packages (authentication required)
- ✅ **Push to production branch** and create release tags
- ❌ **NOT needed** for pulling public packages (deployments work without auth)

**Recommended Approach:**
- Create a dedicated GitHub service account (e.g., `myfinance-ci`) with package write permissions
- Or use a team member's account that will manage releases

1. Go to: **Dashboard → Manage Jenkins → Credentials → System → Global credentials**
2. Click **"Add Credentials"**

**Add GitHub Personal Access Token:**
- Kind: `Username with password`
- Username: `your-github-username` (or service account username)
- Password: `your-github-personal-access-token` (create at https://github.com/settings/tokens)
  - Required permissions: `repo`, `write:packages`, `read:packages`
- ID: `github-token`
- Description: `GitHub Access (Packages & Repository)`
- Click **"Create"**

**Note:** This single credential is used for both pushing Docker images and Git operations.

### Step 2: Verify Plugins (Pre-installed)

The Jenkins Docker image comes with all required plugins pre-installed:
- ✅ Docker Pipeline - For Docker operations
- ✅ Git plugin - For repository access
- ✅ Pipeline plugin - For Jenkinsfile support
- ✅ Node.js plugin - For frontend builds
- ✅ .NET SDK plugin - For backend builds
- ✅ Blue Ocean - Better UI (optional)

**Note:** Plugins are defined in `jenkins/docker/plugins.txt` and installed automatically during container build.

---

## 📁 Create Jenkins Jobs

### Auto-Created Jobs (Recommended)

Jenkins automatically creates jobs on first startup via `init.groovy.d/03-jobs.groovy`:

**MyFinance Folder** containing:
1. **Frontend-Release** - Deploys `myfinance-client` image
2. **Backend-Release** - Deploys `myfinance-server` image

**Go to:** Dashboard → MyFinance folder to see jobs

### Option A: Verify Auto-Created Jobs

1. **Dashboard → MyFinance → Backend-Release**
2. Check configuration:
   - **Image:** `myfinance-server` ✅
   - **Repository:** `https://github.com/rocsa65/MyFinance.git`
   - **Branch:** `staging`
   - **Deployment flow:** Tests → Build → Deploy Green → Migrate → Health Check → Switch

3. **Dashboard → MyFinance → Frontend-Release**
4. Check configuration:
   - **Image:** `myfinance-client` ✅
   - **Repository:** `https://github.com/rocsa65/client.git`
   - **Branch:** `staging`
   - **Deployment flow:** Tests → Build → Deploy Green → Health Check → Switch

### Option B: Manual Job Creation (If Needed)

If auto-creation failed or you need to recreate jobs:

**Backend Release:**
1. **Dashboard → New Item** → Name: `Backend-Release` → Type: **Pipeline**
2. Pipeline script location: `jenkins/pipelines/backend-release.groovy`
3. **Important:** Verify `IMAGE_NAME = 'myfinance-server'` in the pipeline

**Frontend Release:**
1. **Dashboard → New Item** → Name: `Frontend-Release` → Type: **Pipeline**
2. Pipeline script location: `jenkins/pipelines/frontend-release.groovy`
3. **Important:** Verify `IMAGE_NAME = 'myfinance-client'` in the pipeline

---

## 🚀 How to Use Jenkins

### Backend Release

1. Go to **Dashboard → MyFinance → Backend-Release**
2. Click **"Build Now"** (or "Build with Parameters" if available)
3. Monitor the pipeline stages

**What happens:**
```
1. ✅ Checkout - Pulls code from staging branch (rocsa65/MyFinance)
2. ✅ Test - Runs unit tests and integration tests (.NET)
3. ✅ Build and Push - Creates myfinance-server:v{timestamp}-{build} image
4. ✅ Deploy to Green - Deploys to green environment
5. ✅ Database Migration - Runs EF Core migrations on SQLite
6. ✅ Health Check - Verifies API is healthy and SQLite DB exists
7. ✅ Switch Traffic - Routes traffic to green environment
8. ✅ Post-build - Rollback to blue on failure
```

### Frontend Release

1. Go to **Dashboard → MyFinance → Frontend-Release**
2. Click **"Build Now"**
3. Monitor the pipeline stages

**What happens:**
```
1. ✅ Checkout - Pulls code from staging branch (rocsa65/client)
2. ✅ Test - Runs unit tests and integration tests (npm)
3. ✅ UI Tests - Runs E2E tests
4. ✅ Build and Push - Creates myfinance-client:v{timestamp}-{build} image
5. ✅ Deploy to Green - Deploys to green environment
6. ✅ Health Check - Verifies frontend is accessible
7. ✅ Switch Traffic - Routes traffic to green environment
8. ✅ Post-build - Rollback to blue on failure
```

### Option 3: Manual Deployment (No Jenkins)

If Jenkins isn't working, use manual scripts:
```bash
# See GETTING-STARTED.md
bash scripts/deployment/deploy-backend.sh green v1.2.3
```

---

## 📊 Monitor Jenkins Build

### View Build Progress

1. Click on the build number (e.g., #1, #2)
2. Click **"Console Output"** to see logs
3. Watch the progress stages

### Build Stages You'll See:

**Backend Pipeline:**
```
✅ Checkout - Pull code from GitHub
✅ Test - Run .NET unit/integration tests
✅ Build and Push - Build myfinance-server image
✅ Deploy to Green - Deploy to green environment
✅ Database Migration - Run EF Core migrations on SQLite
✅ Health Check - Verify API and SQLite database
✅ Switch Traffic - Route production traffic to green
```

**Frontend Pipeline:**
```
✅ Checkout - Pull code from GitHub
✅ Test - Run npm unit/integration tests
✅ UI Tests - Run E2E tests
✅ Build and Push - Build myfinance-client image
✅ Deploy to Green - Deploy to green environment
✅ Health Check - Verify frontend accessibility
✅ Switch Traffic - Route production traffic to green
```

**Note:** Pipelines run fully automated. No manual approval required (modify pipelines if you want approval gates).

---

## � Docker Package Access

### Public Packages (Current Setup)

**Pulling Images (Deployment):**
- ✅ No authentication needed if packages are public
- ✅ Anyone can deploy using the scripts
- ✅ Perfect for team collaboration

**Pushing Images (Building/Releasing):**
- ⚠️ Authentication **always required** (even for public packages)
- ⚠️ Need GitHub Personal Access Token with `write:packages` permission
- ⚠️ Only authorized users can build and push new versions

### Team Deployment Strategies

**Strategy 1: Jenkins-Only Releases (Recommended)**
```
✅ Developers: Push code to GitHub → No credentials needed
✅ Jenkins: Builds and pushes images → Configured with service account
✅ Team: Deploys from public packages → No credentials needed
```

**Strategy 2: Individual Developer Credentials**
```
Each developer:
1. Creates their own GitHub PAT (write:packages)
2. Configures local .env file
3. Can build and push images independently
```

**Strategy 3: Shared CI/CD Service Account**
```
Team creates:
1. Dedicated GitHub account (e.g., myfinance-ci)
2. Adds it as collaborator with package write access
3. Shares token only with Jenkins and authorized users
```

### Making Packages Public

To allow public access for pulling images:

1. Go to https://github.com/rocsa65?tab=packages
2. Click on package (`myfinance-server` or `myfinance-client`)
3. **Package settings** → **Danger Zone**
4. **Change visibility** → **Public**
5. Confirm the change

**Note:** Even public packages require authentication for pushing new versions.

---

Jenkins needs access to your deployment scripts. The docker-compose already mounts them:

```yaml
volumes:
  - ../../scripts:/var/jenkins_home/scripts
```

This makes all your scripts available to Jenkins at `/var/jenkins_home/scripts/`

---

## �️ Database: SQLite Implementation

MyFinance uses **SQLite** (not PostgreSQL):
- **No separate database containers** - SQLite is embedded in the API
- **Database files:**
  - Blue: `/data/finance_blue.db` (inside myfinance-api-blue container)
  - Green: `/data/finance_green.db` (inside myfinance-api-green container)
- **No DB credentials needed** - SQLite is file-based
- **Docker image:** `myfinance-server` (backend API)
- **Migrations:** Run via EF Core inside the API container
- **Replication:** File copying between containers using `docker cp`

---

## 🐛 Troubleshooting

### Jenkins Won't Start

```powershell
# Check container logs
docker logs myfinance-jenkins

# Restart Jenkins
docker-compose restart jenkins
```

### Can't Access http://localhost:8081

```powershell
# Check if container is running
docker ps | findstr jenkins

# Check port binding
netstat -ano | findstr 8081
```

### Build Fails: "Permission Denied" on Scripts

```bash
# Inside Jenkins container, make scripts executable
docker exec myfinance-jenkins chmod +x /var/jenkins_home/scripts/**/*.sh
```

### Build Fails: "Cannot connect to Docker"

Jenkins needs access to Docker. Check docker-compose.yml has:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

On Windows, make sure Docker Desktop is running and "Expose daemon on tcp://localhost:2375" is enabled in Docker Desktop settings.

### Build Fails: "GitHub Authentication Failed"

**For Pushing Images:**
1. Check credentials in Jenkins (Dashboard → Credentials)
2. Verify GitHub token has these permissions:
   - ✅ `repo` (full control)
   - ✅ `write:packages` (required for push)
   - ✅ `read:packages`
3. Ensure token hasn't expired
4. Verify the account has write access to the repository

**For Pulling Images:**
- If packages are **public**: No authentication needed ✅
- If packages are **private**: Need `read:packages` permission

**For Team Members:**
- **Deploying only**: No credentials needed if packages are public
- **Building & pushing**: Each member needs their own GitHub PAT
- **Recommended**: Use Jenkins for all builds, team members only deploy

---

## 🎓 Typical Jenkins Workflow

### First Time Setup

```
1. Start Jenkins              → docker-compose up -d
2. Access Jenkins             → http://localhost:8081
3. Install plugins            → Docker, Git, Pipeline
4. Add GitHub credentials     → github-token, github-packages
5. Create pipeline jobs       → MyFinance-Release, Backend-Release, Frontend-Release
6. Test with manual build     → Build with Parameters
```

### Regular Release Workflow

**Backend Release:**
```
1. Developer pushes to staging branch (rocsa65/MyFinance)
2. Go to Jenkins → MyFinance → Backend-Release
3. Click "Build Now"
4. Jenkins runs all tests automatically
5. Jenkins builds myfinance-server Docker image
6. Jenkins pushes to GitHub Packages
7. Jenkins deploys to green environment
8. Jenkins runs SQLite migrations
9. Jenkins verifies health (API + SQLite DB)
10. Jenkins switches traffic to green
11. Done! ✅ (Automatic rollback to blue on failure)
```

**Frontend Release:**
```
1. Developer pushes to staging branch (rocsa65/client)
2. Go to Jenkins → MyFinance → Frontend-Release
3. Click "Build Now"
4. Jenkins runs unit/integration/E2E tests
5. Jenkins builds myfinance-client Docker image
6. Jenkins pushes to GitHub Packages
7. Jenkins deploys to green environment
8. Jenkins verifies frontend accessibility
9. Jenkins switches traffic to green
10. Done! ✅ (Automatic rollback to blue on failure)
```

### Emergency Rollback

If Jenkins detects issues during monitoring:
```
1. Automatic rollback triggered
2. Traffic switched back to blue
3. Notification sent
4. Check logs: docker logs myfinance-jenkins
```

---

## 📂 Important Files

### Jenkins Configuration
- `jenkins/docker/docker-compose.yml` - Jenkins container setup
- `jenkins/docker/Dockerfile` - Custom Jenkins image with Node.js, .NET SDK
- `jenkins/docker/plugins.txt` - Pre-installed Jenkins plugins
- `jenkins/docker/init.groovy.d/01-security.groovy` - Security configuration
- `jenkins/docker/init.groovy.d/02-tools.groovy` - Tool installations
- `jenkins/docker/init.groovy.d/03-jobs.groovy` - Auto-created pipeline jobs
- `jenkins/pipelines/backend-release.groovy` - Backend pipeline (myfinance-server)
- `jenkins/pipelines/frontend-release.groovy` - Frontend pipeline (myfinance-client)

### Scripts Used by Jenkins
- `scripts/deployment/deploy-backend.sh` - Deploy backend
- `scripts/deployment/deploy-frontend.sh` - Deploy frontend
- `scripts/database/migrate.sh` - Run migrations
- `scripts/database/replicate.sh` - Copy database
- `scripts/deployment/blue-green-switch.sh` - Switch traffic
- `scripts/monitoring/health-check.sh` - Health checks
- `scripts/deployment/rollback.sh` - Rollback

---

## 🎯 Next Steps

1. ✅ **Start Jenkins:** `docker-compose up -d`
2. ✅ **Configure:** Add GitHub credentials
3. ✅ **Create Jobs:** MyFinance-Release pipeline
4. ✅ **Test:** Run a build manually
5. ✅ **Automate:** Set up webhooks for automatic builds on push

---

## 🔗 Additional Resources

- **Manual Deployment:** See `GETTING-STARTED.md`
- **Quick Reference:** See `QUICK-REFERENCE.md`
- **Pipeline Details:** See `docs/cicd-architecture.md`
- **Blue-Green Flow:** See `docs/blue-green-flow.md`

---

## 💡 Pro Tips

- **Use Blue Ocean UI:** Install Blue Ocean plugin for better visualization
- **Set up webhooks:** Auto-trigger builds on Git push
- **Email notifications:** Configure SMTP for build notifications
- **Backup Jenkins:** Regularly backup `/var/jenkins_home`
- **Monitor builds:** Check Console Output for detailed logs
- **Parameterized builds:** Use parameters for flexible deployments

---

## 🆘 Need Help?

**Jenkins not working?**
```powershell
# Check Jenkins logs
docker logs myfinance-jenkins --tail 100

# Restart Jenkins
docker-compose restart jenkins

# Access Jenkins container
docker exec -it myfinance-jenkins bash
```

**Build failing?**
- Check Console Output in Jenkins
- Verify GitHub credentials
- Ensure Docker is running
- Check script permissions
- Verify .env file is configured

**Still stuck?**
Use manual deployment: See `GETTING-STARTED.md`
