#!/bin/bash

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Create a new user
read -p "Please enter the username for the deploy user (default: deployer): " deploy_user
deploy_user=${deploy_user:-deployer}

echo -e "${BLUE}Creating user '$deploy_user'...${NC}"
sudo adduser --disabled-password --gecos "" $deploy_user
sudo usermod -aG sudo $deploy_user
echo -e "${GREEN}User '$deploy_user' created and added to sudo group.${NC}"

# Step 2: Generate SSH key
echo -e "${BLUE}Generating SSH key for $deploy_user...${NC}"
sudo -u $deploy_user ssh-keygen -t rsa -b 4096 -C "exp@exp.com" -N "" -f /home/$deploy_user/.ssh/id_rsa

echo -e "${BLUE}Here is the SSH public key. Please add it to your GitLab account:${NC}"
cat /home/$deploy_user/.ssh/id_rsa.pub
read -p "Press enter after you've added the SSH key to GitLab..."

# Step 3: Clone the GitLab repository
read -p "Please enter your GitLab repository URL: " gitlab_repo_url

echo -e "${BLUE}Cloning the repository...${NC}"
sudo -u $deploy_user git clone $gitlab_repo_url /home/$deploy_user/project

if [ $? -eq 0 ];then
    echo -e "${GREEN}Repository cloned successfully.${NC}"
else
    echo -e "${RED}Failed to clone the repository. Please check the URL and SSH key.${NC}"
    exit 1
fi

# Step 4: Install Docker
echo -e "${BLUE}Installing Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
sudo usermod -aG docker $deploy_user
echo -e "${GREEN}Docker installed successfully.${NC}"

# Step 5: Clean up .bash_logout file
if [ -f "/home/$deploy_user/.bash_logout" ]; then
    echo -e "${BLUE}Cleaning up .bash_logout to prevent environment preparation issues...${NC}"
    sudo sh -c 'echo "" > /home/$deploy_user/.bash_logout'
    echo -e "${GREEN}.bash_logout file has been cleaned up successfully.${NC}"
fi

# Step 6: Install UFW and configure firewall rules
echo -e "${BLUE}Installing UFW and configuring firewall...${NC}"
sudo apt update && sudo apt install -y ufw
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 23232/tcp
sudo ufw enable
echo -e "${GREEN}UFW installed and configured successfully.${NC}"

# Step 7: Change SSH port to 23232
echo -e "${BLUE}Changing SSH port to 23232...${NC}"
sudo sed -i 's/#Port 22/Port 23232/' /etc/ssh/sshd_config
sudo systemctl restart ssh
echo -e "${GREEN}SSH port changed to 23232 and service restarted.${NC}"

# Step 8: Install and configure GitLab Runner
if command -v gitlab-runner >/dev/null 2>&1; then
    echo -e "${RED}GitLab Runner is already installed. Skipping installation.${NC}"
else
    echo -e "${BLUE}Installing GitLab Runner...${NC}"
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
    echo -e "${GREEN}GitLab Runner installed successfully.${NC}"
fi

# Stop GitLab Runner if it's running
echo -e "${BLUE}Stopping GitLab Runner if it's running...${NC}"
sudo gitlab-runner stop

# Ensure old config.toml is backed up and removed
if [ -f "/etc/gitlab-runner/config.toml" ]; then
    echo -e "${RED}Old config.toml file found. Backing up and removing it...${NC}"
    sudo mv /etc/gitlab-runner/config.toml /etc/gitlab-runner/config.toml.bak
fi

# Install and start GitLab Runner as a service
echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
sudo gitlab-runner install --user=$deploy_user --working-directory=/home/$deploy_user
sudo gitlab-runner start

# Check if GitLab Runner is running
if sudo systemctl is-active --quiet gitlab-runner; then
    echo -e "${GREEN}GitLab Runner is running successfully.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start. Please check the logs for more details.${NC}"
    exit 1
fi

# Register GitLab Runner
echo -e "${BLUE}Please enter your GitLab Runner registration token:${NC}"
read registration_token

sudo gitlab-runner register --non-interactive \
  --url "https://gitlab.com/" \
  --registration-token "$registration_token" \
  --executor "shell" \
  --description "My Server Runner" \
  --tag-list "server" \
  --run-untagged="true" \
  --locked="false"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}GitLab Runner registered successfully.${NC}"
else
    echo -e "${RED}Failed to register GitLab Runner. Please check the provided token and try again.${NC}"
    exit 1
fi

# Final check if GitLab Runner is running
sudo systemctl restart gitlab-runner
if sudo systemctl is-active --quiet gitlab-runner; then
    echo -e "${GREEN}GitLab Runner is running and ready to accept jobs.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start after registration. Please check the logs for more details.${NC}"
    exit 1
fi

echo -e "${GREEN}Setup completed successfully.${NC}"
