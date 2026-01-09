
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export JENKINS_HOME="/var/lib/jenkins"

# Expect from caller: ADMIN_USER, ADMIN_PASS, REPO_URL, REPO_BRANCH, JOB_NAME, SSH_KEY_PATH

# --- Base deps ---
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl git unzip gnupg openjdk-17-jre

# --- Jenkins repo + install ---
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt-get update -y
sudo apt-get install -y jenkins

# --- Disable setup wizard BEFORE first start (recommended) ---
# This avoids the unlock flow and makes Groovy init deterministic
echo "2.0" | sudo tee "${JENKINS_HOME}/jenkins.install.UpgradeWizard.state" >/dev/null
echo "2.0" | sudo tee "${JENKINS_HOME}/jenkins.install.InstallUtil.lastExecVersion" >/dev/null
sudo sed -i 's/runSetupWizard=true/runSetupWizard=false/' /etc/default/jenkins || true

# --- Preinstall required plugins using the Plugin Installation Manager (no HTTP CLI, no docker-only CLI) ---
# On APT-based Jenkins, 'jenkins-plugin-cli' binary is not available. Use the official Plugin Manager JAR instead.
# Ref: Plugin Installation Manager Tool (JAR) — resolves dependencies automatically.
sudo systemctl stop jenkins || true

# Try GitHub "latest" release asset first; if it fails, fallback to an explicit version tag.
# You can override PIM_VER by exporting it in the SSH call (e.g., PIM_VER=2.12.12).
PIM_VER="${PIM_VER:-2.12.12}"

if curl -fL \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/latest/download/jenkins-plugin-manager.jar" \
  -o /tmp/jenkins-plugin-manager.jar; then
  echo "Downloaded Plugin Manager from GitHub (latest)."
else
  echo "GitHub latest asset not found, falling back to explicit version v${PIM_VER}..."
  curl -fL \
    "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/v${PIM_VER}/jenkins-plugin-manager-${PIM_VER}.jar" \
    -o /tmp/jenkins-plugin-manager.jar
fi

# Install plugins directly into $JENKINS_HOME/plugins with correct ownership
sudo -u jenkins java -jar /tmp/jenkins-plugin-manager.jar \
  --war /usr/share/jenkins/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins \
  git workflow-aggregator credentials credentials-binding ssh-credentials ssh-agent

sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins

# --- First start (now that wizard is disabled and plugins are present) ---
sudo systemctl enable jenkins
sudo systemctl start jenkins

# --- Wait for Jenkins HTTP to be up ---
for i in {1..30}; do
  if curl -fsS "http://localhost:8080/login" >/dev/null; then
    echo "Jenkins HTTP is up."
    break
  fi
  echo "Waiting for Jenkins HTTP..."
  sleep 5
done

# --- Prepare PEM for Jenkins credential ---
sudo mkdir -p "${JENKINS_HOME}/keys"
sudo cp -f "$SSH_KEY_PATH" "${JENKINS_HOME}/keys/aws_key.pem"
sudo chmod 600 "${JENKINS_HOME}/keys/aws_key.pem"

# --- Groovy init: admin + SSH credential + pipeline job ---
sudo mkdir -p "${JENKINS_HOME}/init.groovy.d"
sudo tee "${JENKINS_HOME}/init.groovy.d/01-bootstrap.groovy" >/dev/null <<'EOF'
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
def BRANCH     = env["REPO_BRANCH"] ?: "main"
def JOB_NAME   = env["JOB_NAME"]    ?: "main-pipeline"
def KEY_PATH   = "/var/lib/jenkins/keys/aws_key.pem"

def instance = Jenkins.get()

// Admin user + secure strategy
def realm = new HudsonPrivateSecurityRealm(false)
if (realm.getUser(ADMIN_USER) == null) {
  realm.createAccount(ADMIN_USER, ADMIN_PASS)
}
instance.setSecurityRealm(realm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()

// SSH credential
def pem = new File(KEY_PATH).text
def store = SystemCredentialsProvider.getInstance()
if (!store.getCredentials().any { it.id == "aws-ssh-key" }) {
  def creds = new BasicSSHUserPrivateKey(
    CredentialsScope.GLOBAL,
    "aws-ssh-key",
    "ubuntu",
    new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(pem),
    null,
    "AWS SSH Key"
  )
  store.getCredentials().add(creds)
  store.save()
}

// Pipeline job from SCM
def job = instance.getItem(JOB_NAME) as WorkflowJob
if (job == null) {
  job = instance.createProject(WorkflowJob.class, JOB_NAME)
}
def scm = new GitSCM([new UserRemoteConfig(REPO_URL, null, null, null)],
                     [new BranchSpec("*/" + BRANCH)], false, [], null, null, [])
def flow = new CpsScmFlowDefinition(scm, "jenkins/Jenkinsfile")
flow.setLightweight(true)
job.setDefinition(flow)
job.save()
job.scheduleBuild2(0) // auto-trigger first build
EOF

# --- Fix ownership and restart to apply init.groovy ---
sudo chown -R jenkins:jenkins "$JENKINS_HOME"
sudo systemctl restart jenkins

# --- Wait again after restart (init.groovy executes here) ---
for i in {1..30}; do
