# =============================================================================
# Leet-Jenkins: Custom Jenkins Image with Pre-installed Plugins
# =============================================================================
# This Dockerfile builds a Jenkins image with:
#   - All plugins pre-installed (faster startup)
#   - JCasC configuration baked in
#   - Optimal JVM settings
#
# Build: docker build -t leet-jenkins:latest .
# =============================================================================

FROM jenkins/jenkins:lts-jdk17

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG="/var/jenkins_config"

# Copy plugins list and install
COPY config/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy JCasC configuration
COPY config/casc.yaml /var/jenkins_config/casc.yaml

# Set ownership
USER root
RUN chown -R jenkins:jenkins /var/jenkins_config
USER jenkins

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -fsS http://localhost:8080/login || exit 1

EXPOSE 8080 50000
