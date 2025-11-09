#!/bin/bash

# Load Environment Variables
# This script loads environment-specific configuration

ENVIRONMENT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Error: Environment parameter required"
    echo "Usage: source $0 <development|staging|production>"
    return 1 2>/dev/null || exit 1
fi

ENV_FILE="$PROJECT_ROOT/environments/$ENVIRONMENT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Environment file not found: $ENV_FILE"
    return 1 2>/dev/null || exit 1
fi

echo "Loading environment variables from: $ENV_FILE"

# Export variables from .env file
set -a
source "$ENV_FILE"
set +a

# Set derived variables
export PROJECT_ROOT
export SCRIPT_DIR
export ENVIRONMENT

# Create logs directory
mkdir -p "$PROJECT_ROOT/logs"

# Set Docker registry credentials if available
if [[ -n "$GITHUB_PACKAGES_TOKEN" && -n "$GITHUB_PACKAGES_USER" ]]; then
    echo "Docker registry credentials available"
    export DOCKER_REGISTRY_USER="$GITHUB_PACKAGES_USER"
    export DOCKER_REGISTRY_TOKEN="$GITHUB_PACKAGES_TOKEN"
fi

# Validate required variables
REQUIRED_VARS=(
    "DOCKER_REGISTRY"
    "API_BASE_URL"
    "CLIENT_BASE_URL"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo "Error: Missing required environment variables:"
    printf ' - %s\n' "${MISSING_VARS[@]}"
    return 1 2>/dev/null || exit 1
fi

echo "Environment '$ENVIRONMENT' loaded successfully"
echo "Docker Registry: $DOCKER_REGISTRY"
echo "API Base URL: $API_BASE_URL"
echo "Client Base URL: $CLIENT_BASE_URL"