import jenkins.model.*
import hudson.tools.*
import hudson.plugins.nodejs.*
import hudson.plugins.nodejs.tools.*

def instance = Jenkins.getInstance()

// Configure Node.js
def nodeJsInstaller = new NodeJSInstaller("18.19.0", "", 100)
def nodeJsInstallation = new NodeJSInstallation(
    "Node 18", 
    "", 
    [new InstallSourceProperty([nodeJsInstaller])]
)

def nodeJsDescriptor = instance.getDescriptor(NodeJSInstallation.class)
nodeJsDescriptor.setInstallations(nodeJsInstallation)
nodeJsDescriptor.save()

// Configure .NET
// Note: .NET is installed via Dockerfile, this just configures global tools
def dotnetTool = new ToolProperty()

instance.save()

println "Jenkins tools configured"