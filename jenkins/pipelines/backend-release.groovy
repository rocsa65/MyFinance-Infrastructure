pipeline {
    agent any
    
    parameters {
        string(name: 'RELEASE_NUMBER', defaultValue: '', description: 'Release number to deploy')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'SKIP_MIGRATION', defaultValue: false, description: 'Skip database migration')
    }
    
    environment {
        GITHUB_REPO = 'rocsa65/server'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-api'
    }
    
    stages {
        stage('Checkout Staging') {
            steps {
                git branch: 'staging', url: "https://github.com/${env.GITHUB_REPO}.git"
            }
        }
        
        stage('Restore Dependencies') {
            steps {
                script {
                    sh 'dotnet restore MyFinance.sln'
                }
            }
        }
        
        stage('Build') {
            steps {
                script {
                    sh 'dotnet build MyFinance.sln --configuration Release --no-restore'
                }
            }
        }
        
        stage('Unit Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    sh 'dotnet test MyFinance.UnitTests/MyFinance.UnitTests.csproj --configuration Release --no-build --logger trx --results-directory ./TestResults/Unit'
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'TestResults/Unit/*.trx'
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    // Set up test database
                    sh 'export ASPNETCORE_ENVIRONMENT=Testing'
                    sh 'dotnet test MyFinance.IntegrationTests/MyFinance.IntegrationTests.csproj --configuration Release --no-build --logger trx --results-directory ./TestResults/Integration'
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'TestResults/Integration/*.trx'
                }
            }
        }
        
        stage('API Health Check Test') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    // Start the API in test mode and verify health endpoint
                    sh '''
                        export ASPNETCORE_ENVIRONMENT=Testing
                        dotnet run --project MyFinance.Api/MyFinance.Api.csproj --configuration Release &
                        APP_PID=$!
                        
                        # Wait for app to start
                        sleep 30
                        
                        # Check health endpoint
                        curl -f http://localhost:5000/health || exit 1
                        
                        # Stop the app
                        kill $APP_PID
                    '''
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
                    
                    echo "Building backend with release number: ${releaseNumber}"
                    
                    // Build production Docker image
                    sh "docker build -t ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${releaseNumber} -f MyFinance.Api/Dockerfile ."
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
                    withCredentials([usernamePassword(credentialsId: 'github-packages', usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                        sh "echo ${GITHUB_TOKEN} | docker login ghcr.io -u ${GITHUB_USER} --password-stdin"
                        sh "docker push ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${env.RELEASE_NUMBER}"
                        sh "docker push ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:latest"
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
                            git tag -a 'backend-${env.RELEASE_NUMBER}' -m 'Backend Release ${env.RELEASE_NUMBER}'
                            
                            # Switch to production and merge staging
                            git fetch origin
                            git checkout production
                            git merge staging --no-ff -m 'Backend Release ${env.RELEASE_NUMBER}'
                            
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
                    echo "Deploying backend to green environment"
                    sh "/var/jenkins_home/scripts/deployment/deploy-backend.sh green ${env.RELEASE_NUMBER}"
                }
            }
        }
        
        stage('Database Migration') {
            when {
                not { params.SKIP_MIGRATION }
            }
            steps {
                script {
                    echo "Running database migrations on green environment"
                    sh "/var/jenkins_home/scripts/database/migrate.sh green"
                }
            }
        }
        
        stage('Health Check Green') {
            steps {
                script {
                    echo "Performing health check on green environment"
                    sh "/var/jenkins_home/scripts/monitoring/health-check.sh backend green"
                }
            }
        }
        
        stage('Integration Test Green') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running integration tests against green environment"
                    sh "/var/jenkins_home/scripts/monitoring/integration-test.sh green"
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo "Backend release pipeline completed successfully"
                currentBuild.description = "Backend Release ${env.RELEASE_NUMBER}"
            }
        }
        
        failure {
            script {
                echo "Backend release pipeline failed"
                sh "/var/jenkins_home/scripts/monitoring/notify-failure.sh backend ${env.RELEASE_NUMBER}"
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