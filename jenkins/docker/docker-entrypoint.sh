#!/bin/bash
set -e

# Fix Docker socket permissions (running as root)
if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    
    echo "Docker socket GID: ${DOCKER_SOCK_GID}"
    
    # If GID is 0 (root), just add jenkins to root group
    # Otherwise, create/modify docker group with correct GID
    if [ "${DOCKER_SOCK_GID}" = "0" ]; then
        echo "Docker socket owned by root (GID 0), adding jenkins to root group"
        usermod -aG root jenkins
    else
        # Create or update docker group with the correct GID
        if getent group docker > /dev/null 2>&1; then
            groupmod -g ${DOCKER_SOCK_GID} docker
        else
            groupadd -g ${DOCKER_SOCK_GID} docker
        fi
        
        # Add jenkins user to docker group
        usermod -aG docker jenkins
    fi
    
    echo "Docker socket permissions fixed"
fi

# Switch to jenkins user and execute the original Jenkins entrypoint
exec su -s /bin/bash jenkins -c "/usr/bin/tini -- /usr/local/bin/jenkins.sh $*"
