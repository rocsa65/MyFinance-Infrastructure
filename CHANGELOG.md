# MyFinance Infrastructure Changelog

All notable changes to the infrastructure will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial infrastructure repository setup
- Docker configurations for blue-green deployment
- Jenkins CI/CD pipelines for backend and frontend (separate deployments)
- Automated deployment scripts (deploy-backend.sh, deploy-frontend.sh, blue-green-switch.sh)
- Database migration automation (migrate.sh)
- Health check and monitoring scripts
- Integration test automation
- Automatic rollback on deployment failures
- nginx reverse proxy configuration with blue-green support
- Comprehensive documentation (DEPLOYMENT-GUIDE.md, QUICK-REFERENCE.md, blue-green-flow.md, script-flow.md)
- Jenkins Docker setup with automated job creation
- GitHub Container Registry integration
- SQLite database support with independent databases per environment

### Changed

### Deprecated

### Removed

### Fixed

### Security