import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def instance = Jenkins.getInstance()

// Create folder for MyFinance pipelines
def folder = instance.createProject(com.cloudbees.hudson.plugins.folder.Folder.class, "MyFinance")
folder.setDescription("MyFinance application pipelines")

// Frontend Release Pipeline
def frontendJob = folder.createProject(WorkflowJob.class, "Frontend-Release")
frontendJob.setDescription("MyFinance Frontend Release Pipeline")
def frontendScript = '''
pipeline {
    agent any
    
    environment {
        GITHUB_REPO = 'rocsa65/client'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-client'
    }
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'staging', url: "https://github.com/${env.GITHUB_REPO}.git"
            }
        }
        
        stage('Test') {
            steps {
                script {
                    sh 'npm ci'
                    sh 'npm run test:unit'
                    sh 'npm run test:integration'
                }
            }
        }
        
        stage('UI Tests') {
            steps {
                script {
                    sh 'npm run test:e2e'
                }
            }
        }
        
        stage('Build and Push') {
            when {
                allOf {
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    def releaseNumber = generateReleaseNumber()
                    env.RELEASE_NUMBER = releaseNumber
                    
                    sh "docker build -t ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${releaseNumber} ."
                    sh "docker push ${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${releaseNumber}"
                    
                    // Tag and push to production branch
                    sh "git config user.email 'jenkins@myfinance.com'"
                    sh "git config user.name 'Jenkins Release Manager'"
                    sh "git tag -a 'frontend-${releaseNumber}' -m 'Release ${releaseNumber}'"
                    sh "git checkout production"
                    sh "git merge staging --no-ff -m 'Release ${releaseNumber}'"
                    sh "git push origin production --tags"
                }
            }
        }
        
        stage('Deploy to Green') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/deployment/deploy-frontend.sh green ${env.RELEASE_NUMBER}'
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/monitoring/health-check.sh frontend green'
                }
            }
        }
        
        stage('Switch Traffic') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/deployment/blue-green-switch.sh green'
                }
            }
        }
    }
    
    post {
        failure {
            script {
                sh '/var/jenkins_home/scripts/deployment/rollback.sh blue'
            }
        }
    }
}

def generateReleaseNumber() {
    def timestamp = new Date().format("yyyyMMdd-HHmmss")
    def buildNumber = env.BUILD_NUMBER
    return "v${timestamp}-${buildNumber}"
}
'''
frontendJob.setDefinition(new CpsFlowDefinition(frontendScript, true))

// Backend Release Pipeline
def backendJob = folder.createProject(WorkflowJob.class, "Backend-Release")
backendJob.setDescription("MyFinance Backend Release Pipeline")
def backendScript = '''
pipeline {
    agent any
    
    parameters {
        string(name: 'RELEASE_NUMBER', defaultValue: '', description: 'Release number to deploy')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'SKIP_MIGRATION', defaultValue: false, description: 'Skip database migration')
        booleanParam(name: 'AUTO_SWITCH_TRAFFIC', defaultValue: false, description: 'Automatically switch traffic without approval')
    }
    
    environment {
        GITHUB_REPO = 'rocsa65/MyFinance'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-server'
    }
    
    stages {
        stage('Determine Target Environment') {
            steps {
                script {
                    echo "Detecting which environment is currently live..."
                    
                    def nginxConfig = readFile('/var/jenkins_home/docker/nginx/blue-green.conf')
                    
                    def blueActive = nginxConfig.contains('server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;') && 
                                     !nginxConfig.contains('# server myfinance-api-blue:80 max_fails=1 fail_timeout=10s;')
                    
                    def greenActive = nginxConfig.contains('server myfinance-api-green:80 max_fails=1 fail_timeout=10s;') && 
                                      !nginxConfig.contains('# server myfinance-api-green:80 max_fails=1 fail_timeout=10s;')
                    
                    if (blueActive && !greenActive) {
                        env.TARGET_ENV = 'green'
                        env.CURRENT_ENV = 'blue'
                        env.IS_FIRST_DEPLOYMENT = 'false'
                    } else if (greenActive && !blueActive) {
                        env.TARGET_ENV = 'blue'
                        env.CURRENT_ENV = 'green'
                        env.IS_FIRST_DEPLOYMENT = 'false'
                    } else {
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
        
        stage('Build') {
            steps {
                script {
                    echo "Building backend application"
                    sh 'dotnet build MyFinance.sln --configuration Release'
                }
            }
        }
        
        stage('Test') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running backend tests"
                    catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
                        sh 'dotnet test MyFinance.sln --configuration Release --no-build --logger "console;verbosity=detailed"'
                    }
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
                            
                            git tag -a 'backend-${env.RELEASE_NUMBER}' -m 'Backend Release ${env.RELEASE_NUMBER}'
                            
                            git fetch origin
                            git checkout production
                            git merge staging --no-ff -m 'Backend Release ${env.RELEASE_NUMBER}'
                            
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
                    echo "Deploying backend to ${env.TARGET_ENV} environment"
                    echo "Current live environment (${env.CURRENT_ENV}) will remain serving traffic during deployment"
                    sh "/var/jenkins_home/scripts/deployment/deploy-backend.sh ${env.TARGET_ENV} ${env.RELEASE_NUMBER}"
                }
            }
        }
        
        stage('Database Migration') {
            when {
                expression { !params.SKIP_MIGRATION }
            }
            steps {
                script {
                    echo "Running database migrations on ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/database/migrate.sh ${env.TARGET_ENV}"
                }
            }
        }
        
        stage('Health Check Target') {
            steps {
                script {
                    echo "Performing health check on ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/monitoring/health-check.sh backend ${env.TARGET_ENV}"
                }
            }
        }
        
        stage('Integration Test Target') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "Running integration tests against ${env.TARGET_ENV} environment"
                    sh "/var/jenkins_home/scripts/monitoring/integration-test.sh ${env.TARGET_ENV}"
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
                        submitter: "admin",
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
                    sh "/var/jenkins_home/scripts/deployment/blue-green-switch.sh ${env.TARGET_ENV}"
                    
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
'''
backendJob.setDefinition(new CpsFlowDefinition(backendScript, true))

instance.save()

println "Jenkins jobs configured"