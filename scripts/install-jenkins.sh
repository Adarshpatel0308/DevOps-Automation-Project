
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export JENKINS_HOME="/var/lib/jenkins"

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl git unzip gnupg openjdk-17-jre

sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null

sudo apt-get update -y
sudo apt-get install -y jenkins

sudo systemctl stop jenkins || true

sudo jenkins-plugin-cli --plugins \
  git workflow-aggregator credentials credentials-binding ssh-credentials ssh-agent

echo "2.0" | sudo tee "${JENKINS_HOME}/jenkins.install.UpgradeWizard.state"
echo "2.0" | sudo tee "${JENKINS_HOME}/jenkins.install.InstallUtil.lastExecVersion"
sudo sed -i 's/runSetupWizard=true/runSetupWizard=false/' /etc/default/jenkins || true

sudo mkdir -p "${JENKINS_HOME}/keys"
sudo cp "$SSH_KEY_PATH" "${JENKINS_HOME}/keys/aws_key.pem"
sudo chmod 600 "${JENKINS_HOME}/keys/aws_key.pem"

sudo mkdir -p "${JENKINS_HOME}/init.groovy.d"

sudo tee "${JENKINS_HOME}/init.groovy.d/01-bootstrap.groovy" >/dev/null <<EOF
import jenkins.model.*
import hudson.security.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.*

def env = System.getenv()
def ADMIN_USER = env["ADMIN_USER"]
def ADMIN_PASS = env["ADMIN_PASS"]
def REPO_URL   = env["REPO_URL"]
def BRANCH     = env["REPO_BRANCH"]
def JOB_NAME   = env["JOB_NAME"]
def KEY_PATH   = "/var/lib/jenkins/keys/aws_key.pem"

def instance = Jenkins.get()

def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount(ADMIN_USER, ADMIN_PASS)
instance.setSecurityRealm(realm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()

def pem = new File(KEY_PATH).text
def creds = new BasicSSHUserPrivateKey(
  CredentialsScope.GLOBAL,
  "aws-ssh-key",
  "ubuntu",
  new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(pem),
  null,
  "AWS SSH Key"
)
SystemCredentialsProvider.getInstance().getCredentials().add(creds)
SystemCredentialsProvider.getInstance().save()

def job = instance.getItem(JOB_NAME) as WorkflowJob
if (job == null) job = instance.createProject(WorkflowJob.class, JOB_NAME)

def scm = new GitSCM([new UserRemoteConfig(REPO_URL, null, null, null)],
                     [new BranchSpec("*/${BRANCH}")],
                     false, [], null, null, [])

def flow = new CpsScmFlowDefinition(scm, "jenkins/Jenkinsfile")
flow.setLightweight(true)
job.setDefinition(flow)
job.save()
job.scheduleBuild2(0)
EOF

sudo chown -R jenkins:jenkins "$JENKINS_HOME"
sudo systemctl restart jenkins
