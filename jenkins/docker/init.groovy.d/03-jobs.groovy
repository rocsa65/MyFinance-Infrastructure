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
    
    environment {
        GITHUB_REPO = 'rocsa65/server'
        DOCKER_REGISTRY = 'ghcr.io/rocsa65'
        IMAGE_NAME = 'myfinance-api'
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
                    sh 'dotnet restore'
                    sh 'dotnet test MyFinance.UnitTests/MyFinance.UnitTests.csproj --logger trx --results-directory ./TestResults'
                    sh 'dotnet test MyFinance.IntegrationTests/MyFinance.IntegrationTests.csproj --logger trx --results-directory ./TestResults'
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
                    sh "git tag -a 'backend-${releaseNumber}' -m 'Release ${releaseNumber}'"
                    sh "git checkout production"
                    sh "git merge staging --no-ff -m 'Release ${releaseNumber}'"
                    sh "git push origin production --tags"
                }
            }
        }
        
        stage('Deploy to Green') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/deployment/deploy-backend.sh green ${env.RELEASE_NUMBER}'
                }
            }
        }
        
        stage('Database Migration') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/database/migrate.sh green'
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    sh '/var/jenkins_home/scripts/monitoring/health-check.sh backend green'
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
backendJob.setDefinition(new CpsFlowDefinition(backendScript, true))

instance.save()

println "Jenkins jobs configured"