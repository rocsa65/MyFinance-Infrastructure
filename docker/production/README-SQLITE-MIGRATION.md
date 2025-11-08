# Infrastructure SQLite Migration - Changes Made

##  Completed Changes

### 1. Production Docker Compose (docker/production/docker-compose.yml)
-  Removed PostgreSQL service (myfinance-db)
-  Removed depends_on: - myfinance-db from API service
-  Updated API image name: myfinance-api  myfinance-server
-  Updated connection string: ConnectionStrings__DefaultConnection=Data Source=/data/finance.db
-  Removed PostgreSQL volumes (db_data, db_logs)
-  Kept API data volume: pi_data:/data

### 2. Production Environment (environments/production/.env)
-  Updated DB_CONNECTION_STRING=Data Source=/data/finance.db
-  Updated API_IMAGE_NAME=myfinance-server
-  Commented out PostgreSQL-specific settings
-  Backup created: .env.backup

##  TODO: Remaining Changes

### 1. Blue-Green Deployment Files

#### docker/blue-green/docker-compose.blue.yml
- Remove myfinance-db-blue service
- Remove depends_on: - myfinance-db-blue
- Update API image to myfinance-server
- Update connection string to SQLite
- Remove PostgreSQL volumes

#### docker/blue-green/docker-compose.green.yml
- Same changes as blue.yml

### 2. Manual Steps Required

1. **Update .env file manually**:
   `ash
   cd environments/production
   # Edit .env and verify:
   # - DB_CONNECTION_STRING=Data Source=/data/finance.db
   # - API_IMAGE_NAME=myfinance-server
   `

2. **Test the configuration**:
   `ash
   cd docker/production
   docker-compose config  # Validate YAML syntax
   docker-compose pull     # Pull latest images
   docker-compose up -d    # Start services
   docker-compose logs -f myfinance-api  # Check for migration
   `

3. **Verify database creation**:
   `ash
   docker exec myfinance-api-prod ls -la /data/
   # Should see: finance.db
   `

##  Important Notes

- **Data Persistence**: Database stored in Docker volume pi_data
- **Migrations**: Auto-run on container startup (already configured in Program.cs)
- **Backup Files**: Originals saved as .backup files
- **Image Names**: Match CI pipeline naming (myfinance-server, not myfinance-api)

##  To Deploy

1. Pull latest server image from CI pipeline
2. Start services with updated docker-compose
3. Database will be created automatically
4. Monitor logs for successful migration

