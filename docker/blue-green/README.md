# Blue-Green Deployment Docker Configuration

This directory contains Docker configurations for blue-green deployment of the MyFinance application.

## Overview

The blue-green deployment strategy uses two identical production environments:
- **Blue**: Currently active production environment
- **Green**: Target environment for new deployments

## Files

- `docker-compose.blue.yml`: Blue environment configuration
- `docker-compose.green.yml`: Green environment configuration
- `docker-compose.nginx.yml`: nginx proxy configuration for traffic routing

## Usage

### Deploy to Green Environment
```bash
docker-compose -f docker-compose.green.yml up -d
```

### Switch Traffic to Green
```bash
# Update nginx configuration to point to green
./switch-traffic.sh green
```

### Rollback to Blue
```bash
./switch-traffic.sh blue
```

## Environment Variables

Set these environment variables before deployment:

- `RELEASE_NUMBER`: The release version to deploy
- `DB_CONNECTION_STRING`: Database connection string
- `GITHUB_PACKAGES_TOKEN`: Token for pulling Docker images

## Networks

Both environments use the same external network (`myfinance-network`) to allow nginx proxy to route traffic between them.