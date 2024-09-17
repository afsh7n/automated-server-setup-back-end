#!/bin/bash

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Create a new user
read -p "Please enter the username for the deploy user (default: deployer): " deploy_user
deploy_user=${deploy_user:-deployer}

if id "$deploy_user" &>/dev/null; then
    echo -e "${GREEN}User '$deploy_user' already exists. Skipping user creation.${NC}"
else
    echo -e "${BLUE}Creating user '$deploy_user'...${NC}"
    sudo adduser --disabled-password --gecos "" $deploy_user
    sudo usermod -aG sudo $deploy_user
    echo -e "${GREEN}User '$deploy_user' created and added to sudo group.${NC}"
fi

# Step 2: Generate SSH key for deploy_user and root
if [ -f "/home/$deploy_user/.ssh/id_rsa" ]; then
    echo -e "${GREEN}SSH key for '$deploy_user' already exists. Skipping SSH key generation.${NC}"
else
    echo -e "${BLUE}Generating SSH key for $deploy_user...${NC}"
    sudo -u $deploy_user ssh-keygen -t rsa -b 4096 -C "exp@exp.com" -N "" -f /home/$deploy_user/.ssh/id_rsa
    echo -e "${BLUE}Here is the SSH public key. Please add it to your GitLab account:${NC}"
    cat /home/$deploy_user/.ssh/id_rsa.pub
fi

# Copy SSH key to root's .ssh directory
if [ -f "/root/.ssh/id_rsa" ]; then
    echo -e "${GREEN}SSH key for 'root' already exists. Skipping copying from deploy_user.${NC}"
else
    echo -e "${BLUE}Copying SSH key to root's .ssh directory...${NC}"
    sudo mkdir -p /root/.ssh
    sudo cp /home/$deploy_user/.ssh/id_rsa /root/.ssh/id_rsa
    sudo cp /home/$deploy_user/.ssh/id_rsa.pub /root/.ssh/id_rsa.pub
    sudo cat /home/$deploy_user/.ssh/authorized_keys | sudo tee -a /root/.ssh/authorized_keys
    sudo chmod 600 /root/.ssh/authorized_keys
    sudo chown root:root /root/.ssh/id_rsa /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    echo -e "${GREEN}SSH key copied to root's .ssh directory successfully.${NC}"
fi

read -p "Press enter after you've added the SSH key to GitLab..."

# Step 3: Clone the GitLab repository as root
if [ -d "/home/$deploy_user/$project_name" ]; then
    echo -e "${GREEN}Repository already exists in /home/$deploy_user/$project_name. Skipping clone.${NC}"
else
    read -p "Please enter your GitLab repository URL: " gitlab_repo_url

    # Extract project name from the GitLab URL
    project_name=$(basename -s .git $gitlab_repo_url)

    echo -e "${BLUE}Cloning the repository...${NC}"
    git clone $gitlab_repo_url /home/$deploy_user/$project_name

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Repository cloned successfully to /home/$deploy_user/$project_name.${NC}"
    else
        echo -e "${RED}Failed to clone the repository. Please check the URL and SSH key.${NC}"
        exit 1
    fi
fi

# Step 4: Install Docker
if command -v docker &>/dev/null; then
    echo -e "${GREEN}Docker is already installed. Skipping Docker installation.${NC}"
else
    echo -e "${BLUE}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh ./get-docker.sh
    sudo usermod -aG docker $deploy_user
    echo -e "${GREEN}Docker installed successfully.${NC}"
fi

# Step 5: Install Docker Compose
if command -v docker-compose &>/dev/null; then
    echo -e "${GREEN}Docker Compose is already installed. Skipping Docker Compose installation.${NC}"
else
    echo -e "${BLUE}Installing Docker Compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose installed successfully.${NC}"
fi

# Step 6: Clean up .bash_logout file
if [ -f "/home/$deploy_user/.bash_logout" ] && [ ! -s "/home/$deploy_user/.bash_logout" ]; then
    echo -e "${GREEN}.bash_logout already cleaned. Skipping this step.${NC}"
else
    echo -e "${BLUE}Cleaning up .bash_logout to prevent environment preparation issues...${NC}"
    sudo sh -c 'echo "" > /home/$deploy_user/.bash_logout'
    echo -e "${GREEN}.bash_logout file has been cleaned up successfully.${NC}"
fi

# Step 7: Install UFW and configure firewall rules
if sudo ufw status | grep -q "active"; then
    echo -e "${GREEN}UFW is already active. Skipping UFW installation and configuration.${NC}"
else
    echo -e "${BLUE}Installing UFW and configuring firewall...${NC}"
    sudo apt update && sudo apt install -y ufw
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 23232/tcp
    sudo ufw enable
    echo -e "${GREEN}UFW installed and configured successfully.${NC}"
fi

# Step 8: Change SSH port to 23232
if grep -q "Port 23232" /etc/ssh/sshd_config; then
    echo -e "${GREEN}SSH port is already set to 23232. Skipping this step.${NC}"
else
    echo -e "${BLUE}Changing SSH port to 23232...${NC}"
    sudo sed -i 's/#Port 22/Port 23232/' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo -e "${GREEN}SSH port changed to 23232 and service restarted.${NC}"
fi

# Step 9: Install and configure GitLab Runner
if command -v gitlab-runner >/dev/null 2>&1; then
    echo -e "${GREEN}GitLab Runner is already installed. Skipping installation.${NC}"
else
    echo -e "${BLUE}Installing GitLab Runner...${NC}"
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
    echo -e "${GREEN}GitLab Runner installed successfully.${NC}"
fi

if sudo systemctl is-active --quiet gitlab-runner; then
    echo -e "${GREEN}GitLab Runner is already running. Skipping this step.${NC}"
else
    echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
    sudo gitlab-runner install --user=$deploy_user --working-directory=/home/$deploy_user
    sudo gitlab-runner start

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
fi
