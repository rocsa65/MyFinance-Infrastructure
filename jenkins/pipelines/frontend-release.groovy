pipeline {
    agent any
    
    parameters {
        string(name: 'RELEASE_NUMBER', defaultValue: '', description: 'Release number to deploy')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test execution')
    }
    
    environment {
        GITHUB_REPO = 'rocsa65/client'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-client'
    }
    
    stages {
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
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    sh 'npm run test:unit'
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'coverage/lcov-report/**/*.xml'
                    publishCoverage adapters: [cobertura('coverage/cobertura-coverage.xml')], sourceFileResolver: sourceFiles('STORE_LAST_BUILD')
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    sh 'npm run test:integration'
                }
            }
        }
        
        stage('UI Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    // Start the application for E2E testing
                    sh 'npm run build'
                    sh 'npm run serve:test &'
                    sleep 30 // Wait for app to start
                    
                    // Run Cypress tests
                    sh 'npm run test:e2e:headless'
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'cypress/screenshots/**/*', allowEmptyArchive: true
                    archiveArtifacts artifacts: 'cypress/videos/**/*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Build Production') {
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
        
        stage('Deploy to Green Environment') {
            steps {
                script {
                    echo "Deploying frontend to green environment"
                    sh "/var/jenkins_home/scripts/deployment/deploy-frontend.sh green ${env.RELEASE_NUMBER}"
                }
            }
        }
        
        stage('Health Check Green') {
            steps {
                script {
                    echo "Performing health check on green environment"
                    sh "/var/jenkins_home/scripts/monitoring/health-check.sh frontend green"
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo "Frontend release pipeline completed successfully"
                currentBuild.description = "Frontend Release ${env.RELEASE_NUMBER}"
            }
        }
        
        failure {
            script {
                echo "Frontend release pipeline failed"
                sh "/var/jenkins_home/scripts/monitoring/notify-failure.sh frontend ${env.RELEASE_NUMBER}"
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