
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Update & prerequisites
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl git unzip gnupg openjdk-17-jre

# Jenkins repo + key (GPG keyring — Ubuntu recommended)
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y jenkins

# Enable & start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version || true

# kubectl (latest stable)
KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" -o kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client=true || true

# Allow 8080 if ufw present (usually disabled)
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 8080/tcp || true
fi

# Print Jenkins admin password (sanity)
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
  sudo cat /var/lib/jenkins/secrets/initialAdminPassword || true
fi

echo "Bootstrap complete."
``
