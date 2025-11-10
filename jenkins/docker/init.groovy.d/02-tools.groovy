import jenkins.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()

// NodeJS and other tools will be installed automatically when needed by pipelines
// Or can be configured manually through Jenkins UI after startup

println "Jenkins tools configuration skipped - will be configured through UI"

instance.save()