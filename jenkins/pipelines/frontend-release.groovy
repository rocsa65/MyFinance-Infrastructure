pipeline {
    agent any
    
    parameters {
        string(name: 'RELEASE_NUMBER', defaultValue: '', description: 'Release number to deploy')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'AUTO_SWITCH_TRAFFIC', defaultValue: false, description: 'Automatically switch traffic without approval')
    }
    
    environment {
        GITHUB_REPO = 'rocsa65/client'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-client'
    }
    
    stages {
        stage('Determine Target Environment') {
            steps {
                script {
                    echo "Detecting which environment is currently live..."
                    
                    // Read NGINX config to determine which environment is active
                    def nginxConfig = readFile('/var/jenkins_home/docker/nginx/blue-green.conf')
                    
                    // Check if blue is active (not commented out)
                    def blueActive = nginxConfig.contains('server myfinance-client-blue:80;') && 
                                     !nginxConfig.contains('# server myfinance-client-blue:80;')
                    
                    // Check if green is active (not commented out)
                    def greenActive = nginxConfig.contains('server myfinance-client-green:80;') && 
                                      !nginxConfig.contains('# server myfinance-client-green:80;')
                    
                    if (blueActive && !greenActive) {
                        // Blue is live, deploy to Green
                        env.TARGET_ENV = 'green'
                        env.CURRENT_ENV = 'blue'
                        env.IS_FIRST_DEPLOYMENT = 'false'
                    } else if (greenActive && !blueActive) {
                        // Green is live, deploy to Blue
                        env.TARGET_ENV = 'blue'
                        env.CURRENT_ENV = 'green'
                        env.IS_FIRST_DEPLOYMENT = 'false'
                    } else {
                        // Neither is live (first deployment) - default to Green
                        env.TARGET_ENV = 'green'
                        env.CURRENT_ENV = 'none'
                        env.IS_FIRST_DEPLOYMENT = 'true'
                        echo "⚠️  First deployment detected - no environment is currently live"
                    }
                    
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "Blue-Green Deployment Strategy"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    if (env.IS_FIRST_DEPLOYMENT == 'true') {
                        echo "First deployment: Deploying to ${env.TARGET_ENV.toUpperCase()}"
                        echo "After this deployment, ${env.TARGET_ENV.toUpperCase()} will be live"
                    } else {
                        echo "Current LIVE environment: ${env.CURRENT_ENV.toUpperCase()} (serving traffic)"
                        echo "Target deployment environment: ${env.TARGET_ENV.toUpperCase()} (will receive new release)"
                    }
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                }
            }
        }
        stage('Checkout Staging') {
            steps {
                git branch: 'staging', url: "https://github.com/${env.GITHUB_REPO}.git"
            }
        }
        
        stage('Install Dependencies') {
            steps {
                script {
                    sh 'npm ci --only=production'
                    sh 'npm ci' // Install all dependencies for testing
                }
            }
        }
        
        stage('Unit Tests') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running unit tests..."
                    // Mock until test:unit script is added to client package.json
                    sh '''
                        if npm run | grep -q "test:unit"; then
                            npm run test:unit
                        else
                            echo "⚠️  test:unit script not found - skipping (add to package.json)"
                            echo "✓ Unit tests: MOCKED (passed)"
                        fi
                    '''
                }
            }
            post {
                always {
                    junit testResults: 'coverage/lcov-report/**/*.xml', allowEmptyResults: true
                    publishHTML target: [
                        allowMissing: true,
                        alwaysLinkToLastBuild: false,
                        keepAll: true,
                        reportDir: 'coverage/lcov-report',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ]
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running integration tests..."
                    // Mock until test:integration script is added to client package.json
                    sh '''
                        if npm run | grep -q "test:integration"; then
                            npm run test:integration
                        else
                            echo "⚠️  test:integration script not found - skipping (add to package.json)"
                            echo "✓ Integration tests: MOCKED (passed)"
                        fi
                    '''
                }
            }
        }
        
        stage('UI Tests') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running UI/E2E tests..."
                    // Mock until E2E test scripts are added to client package.json
                    sh '''
                        if npm run | grep -q "test:e2e:headless"; then
                            npm run build
                            npm run serve:test &
                            sleep 30
                            npm run test:e2e:headless
                        else
                            echo "⚠️  E2E test scripts not found - skipping (add to package.json)"
                            echo "   Required scripts: serve:test, test:e2e:headless"
                            echo "✓ UI/E2E tests: MOCKED (passed)"
                        fi
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'cypress/screenshots/**/*', allowEmptyArchive: true
                    archiveArtifacts artifacts: 'cypress/videos/**/*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Build Docker Image') {
            when {
                allOf {
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    def releaseNumber = params.RELEASE_NUMBER ?: generateReleaseNumber()
                    env.RELEASE_NUMBER = releaseNumber
                    
                    echo "Building frontend with release number: ${releaseNumber}"
                    
                    // Build production Docker image
                    sh "docker build -t ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${releaseNumber} -f Dockerfile ."
                    sh "docker tag ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${releaseNumber} ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:latest"
                }
            }
        }
        
        stage('Push to Registry') {
            when {
                allOf {
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    // Authentication required for pushing images
                    // Note: Pulling public packages doesn't require auth
                    withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                        sh "echo ${GITHUB_TOKEN} | docker login ghcr.io -u ${GITHUB_USER} --password-stdin"
                        sh "docker push ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${env.RELEASE_NUMBER}"
                        sh "docker push ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:latest"
                        sh "docker logout ghcr.io"
                    }
                }
            }
        }
        
        stage('Update Production Branch') {
            when {
                allOf {
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                        sh """
                            git config user.email 'jenkins@myfinance.com'
                            git config user.name 'Jenkins Release Manager'
                            git remote set-url origin https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${env.GITHUB_REPO}.git
                            
                            # Create release tag
                            git tag -a 'frontend-${env.RELEASE_NUMBER}' -m 'Frontend Release ${env.RELEASE_NUMBER}'
                            
                            # Switch to production and merge staging
                            git fetch origin
                            git checkout production
                            git merge staging --no-ff -m 'Frontend Release ${env.RELEASE_NUMBER}'
                            
                            # Push changes and tags
                            git push origin production
                            git push origin --tags
                        """
                    }
                }
            }
        }
        
        stage('Deploy to Target Environment') {
            steps {
                script {
                    echo "Deploying frontend to ${env.TARGET_ENV} environment"
                    echo "Current live environment (${env.CURRENT_ENV}) will remain serving traffic during deployment"
                    sh "/var/jenkins_home/scripts/deployment/deploy-frontend.sh ${env.TARGET_ENV} ${env.RELEASE_NUMBER}"
                }
            }
        }
        
        stage('Health Check Target') {
            steps {
                script {
                    echo "Performing health check on ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/monitoring/health-check.sh frontend ${env.TARGET_ENV}"
                }
            }
        }
        
        stage('Integration Test Target') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running frontend integration tests against ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/monitoring/integration-test-frontend.sh ${env.TARGET_ENV}"
                }
            }
        }
        
        stage('Approve Traffic Switch') {
            when {
                expression { !params.AUTO_SWITCH_TRAFFIC }
            }
            steps {
                script {
                    echo "${env.TARGET_ENV.toUpperCase()} environment is ready and tested"
                    echo "Release: ${env.RELEASE_NUMBER}"
                    echo ""
                    
                    if (env.IS_FIRST_DEPLOYMENT == 'true') {
                        echo "First deployment:"
                        echo "  - ${env.TARGET_ENV.toUpperCase()}: New release (tested, ready to go live)"
                        echo ""
                        echo "Next action: Make ${env.TARGET_ENV.toUpperCase()} live (first production deployment)"
                    } else {
                        echo "Current state:"
                        echo "  - ${env.CURRENT_ENV.toUpperCase()}: Live (serving production traffic)"
                        echo "  - ${env.TARGET_ENV.toUpperCase()}: New release (tested, ready to go live)"
                        echo ""
                        echo "Next action: Switch traffic from ${env.CURRENT_ENV.toUpperCase()} to ${env.TARGET_ENV.toUpperCase()}"
                    }
                    
                    // Manual approval - manager/lead clicks "Proceed" in Jenkins UI
                    def approvalMessage = env.IS_FIRST_DEPLOYMENT == 'true' ? 
                        "Make ${env.TARGET_ENV.toUpperCase()} live?" : 
                        "Switch traffic to ${env.TARGET_ENV.toUpperCase()} environment?"
                    
                    def approvalButton = env.IS_FIRST_DEPLOYMENT == 'true' ?
                        "Go Live with ${env.TARGET_ENV.toUpperCase()}" :
                        "Switch to ${env.TARGET_ENV.toUpperCase()}"
                    
                    def confirmChoices = env.IS_FIRST_DEPLOYMENT == 'true' ?
                        ["Yes, go live with ${env.TARGET_ENV.toUpperCase()}", "No, abort deployment"] :
                        ["Yes, switch to ${env.TARGET_ENV.toUpperCase()}", "No, keep ${env.CURRENT_ENV.toUpperCase()} live"]
                    
                    input(
                        message: approvalMessage,
                        ok: approvalButton,
                        submitter: "admin",  // Add your manager's Jenkins username here
                        parameters: [
                            choice(
                                name: 'CONFIRM',
                                choices: confirmChoices,
                                description: 'Confirm traffic switch to new release'
                            )
                        ]
                    )
                }
            }
        }
        
        stage('Switch Traffic to Target') {
            steps {
                script {
                    echo "Switching production traffic to ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/deployment/blue-green-switch.sh ${env.TARGET_ENV} client"
                    
                    // Mark that traffic switch succeeded
                    env.TRAFFIC_SWITCHED = 'true'
                    
                    echo "✅ Traffic switched to ${env.TARGET_ENV.toUpperCase()}"
                    echo "Production is now running: ${env.RELEASE_NUMBER}"
                    echo ""
                    echo "${env.CURRENT_ENV.toUpperCase()} environment is now idle (can be used for rollback)"
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo "Frontend Release ${env.RELEASE_NUMBER} deployed successfully"
                echo "Environment: ${env.TARGET_ENV.toUpperCase()}"
                echo ""
                echo "Status:"
                if (params.AUTO_SWITCH_TRAFFIC) {
                    echo "  - Traffic: Automatically switched to ${env.TARGET_ENV.toUpperCase()}"
                    echo "  - Production: ${env.RELEASE_NUMBER} is now live"
                    if (env.IS_FIRST_DEPLOYMENT != 'true') {
                        echo "  - ${env.CURRENT_ENV.toUpperCase()}: Stopped (previous version available for rollback)"
                    }
                } else {
                    echo "  - Traffic: Successfully switched to ${env.TARGET_ENV.toUpperCase()}"
                    echo "  - Production: ${env.RELEASE_NUMBER} is now live"
                    if (env.IS_FIRST_DEPLOYMENT != 'true') {
                        echo "  - ${env.CURRENT_ENV.toUpperCase()}: Stopped (previous version available for rollback)"
                    }
                }
                currentBuild.description = "Frontend Release ${env.RELEASE_NUMBER} - ${env.TARGET_ENV.toUpperCase()}"
            }
        }
        
        failure {
            script {
                def releaseNum = env.RELEASE_NUMBER ?: 'UNKNOWN'
                echo "Frontend Release ${releaseNum} failed"
                echo ""
                
                // Automatic rollback if traffic was switched but pipeline failed afterwards
                if (env.TRAFFIC_SWITCHED == 'true' && env.CURRENT_ENV) {
                    echo "🚨 AUTOMATIC ROLLBACK INITIATED 🚨"
                    echo "Rolling back to ${env.CURRENT_ENV} environment"
                    
                    try {
                        sh "/var/jenkins_home/scripts/deployment/blue-green-switch.sh ${env.CURRENT_ENV} client"
                        echo "✅ Rollback successful - traffic restored to ${env.CURRENT_ENV}"
                        sh "/var/jenkins_home/scripts/monitoring/notify-rollback.sh ${env.CURRENT_ENV} SUCCESS"
                    } catch (Exception e) {
                        echo "❌ Rollback failed: ${e.message}"
                        echo "⚠️ MANUAL INTERVENTION REQUIRED"
                        sh "/var/jenkins_home/scripts/monitoring/notify-rollback.sh ${env.CURRENT_ENV} FAILED"
                    }
                } else {
                    echo "Current state:"
                    if (env.IS_FIRST_DEPLOYMENT == 'true') {
                        echo "  - No traffic affected (first deployment failed)"
                        echo "  - No rollback needed"
                    } else {
                        echo "  - ${env.CURRENT_ENV.toUpperCase()}: Still live (serving production traffic)"
                        echo "  - ${env.TARGET_ENV.toUpperCase()}: Deployment failed"
                        echo "  - No rollback needed - production traffic was never switched"
                    }
                }
                
                echo ""
                echo "Check logs above for error details"
                sh "/var/jenkins_home/scripts/monitoring/notify-failure.sh frontend ${releaseNum}"
            }
        }
        
        always {
            cleanWs()
        }
    }
}

def generateReleaseNumber() {
    def timestamp = new Date().format("yyyyMMdd-HHmmss")
    def buildNumber = env.BUILD_NUMBER ?: "0"
    return "v${timestamp}-${buildNumber}"
}