import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def instance = Jenkins.getInstance()

// Create folder for MyFinance pipelines
def folder = instance.createProject(com.cloudbees.hudson.plugins.folder.Folder.class, "MyFinance")
folder.setDescription("MyFinance application pipelines")

// Frontend Release Pipeline - loaded from local file
def frontendJob = folder.createProject(WorkflowJob.class, "Frontend-Release")
frontendJob.setDescription("MyFinance Frontend Release Pipeline")

def frontendScript = new File('/var/jenkins_home/pipelines/frontend-release.groovy').text
def frontendDefinition = new CpsFlowDefinition(frontendScript, true)
frontendJob.setDefinition(frontendDefinition)

// Backend Release Pipeline - loaded from local file
def backendJob = folder.createProject(WorkflowJob.class, "Backend-Release")
backendJob.setDescription("MyFinance Backend Release Pipeline")

def backendScript = new File('/var/jenkins_home/pipelines/backend-release.groovy').text
def backendDefinition = new CpsFlowDefinition(backendScript, true)
backendJob.setDefinition(backendDefinition)

// Full Release Pipeline - orchestrator with RELEASE_TYPE parameter
def fullReleaseJob = folder.createProject(WorkflowJob.class, "Full-Release")
fullReleaseJob.setDescription("MyFinance Full Release Pipeline - Deploy Frontend, Backend, or Both")

def fullReleaseScript = new File('/var/jenkins_home/Jenkinsfile').text
def fullReleaseDefinition = new CpsFlowDefinition(fullReleaseScript, true)
fullReleaseJob.setDefinition(fullReleaseDefinition)

instance.save()

println "Jenkins jobs configured from local pipeline files"
