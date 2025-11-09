FROM jenkins/jenkins:lts-jdk17

# Switch to root user to install additional packages
USER root

# Install Docker CLI and other necessary tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    dos2unix \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli

# Install Docker Compose
RUN curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose \
    && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Install .NET 9 SDK
RUN wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-9.0

# Add jenkins user to docker group with correct GID
# Get the docker group ID from the host's docker.sock
RUN groupadd -f docker || true \
    && usermod -aG docker jenkins \
    && chgrp docker /var/run/docker.sock 2>/dev/null || true \
    && chmod 666 /var/run/docker.sock 2>/dev/null || true

# Copy custom entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy Jenkins plugins list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Copy Jenkins plugins list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Install Jenkins plugins
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy initialization scripts
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# Keep as root user for entrypoint to fix permissions
# Entrypoint will switch to jenkins user after fixing Docker socket

# Set Jenkins environment variables
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV JENKINS_OPTS="--httpPort=8080"

# Use custom entrypoint to fix Docker socket permissions
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
