#!/bin/bash

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Summary variables
SUCCESS_STEPS=()
FAILED_STEPS=()

function log_success() {
    SUCCESS_STEPS+=("$1")
    echo -e "${GREEN}$1${NC}"
}

function log_fail() {
    FAILED_STEPS+=("$1")
    echo -e "${RED}$1${NC}"
}

# Step 1: Create a new user
read -p "Please enter the username for the deploy user (default: deployer): " deploy_user
deploy_user=${deploy_user:-deployer}

if id "$deploy_user" &>/dev/null; then
    log_success "User '$deploy_user' already exists. Skipping user creation."
else
    echo -e "${BLUE}Creating user '$deploy_user'...${NC}"
    sudo adduser --disabled-password --gecos "" $deploy_user
    sudo usermod -aG sudo $deploy_user
    if [ $? -eq 0 ]; then
        log_success "User '$deploy_user' created and added to sudo group."
    else
        log_fail "Failed to create user '$deploy_user'. Exiting..."
        exit 1
    fi
fi

# Step 2: Generate SSH key for deploy_user and root
if [ -f "/home/$deploy_user/.ssh/id_rsa" ]; then
    log_success "SSH key for '$deploy_user' already exists. Skipping SSH key generation."
else
    echo -e "${BLUE}Generating SSH key for $deploy_user...${NC}"
    sudo -u $deploy_user ssh-keygen -t rsa -b 4096 -C "exp@exp.com" -N "" -f /home/$deploy_user/.ssh/id_rsa
    echo -e "${BLUE}Here is the SSH public key. Please add it to your GitLab account:${NC}"
    cat /home/$deploy_user/.ssh/id_rsa.pub
fi

# Copy SSH key to root's .ssh directory
if [ -f "/root/.ssh/id_rsa" ]; then
    log_success "SSH key for 'root' already exists. Skipping copying from deploy_user."
else
    echo -e "${BLUE}Copying SSH key to root's .ssh directory...${NC}"
    sudo mkdir -p /root/.ssh
    sudo cp /home/$deploy_user/.ssh/id_rsa /root/.ssh/id_rsa
    sudo cp /home/$deploy_user/.ssh/id_rsa.pub /root/.ssh/id_rsa.pub
    sudo cat /home/$deploy_user/.ssh/authorized_keys | sudo tee -a /root/.ssh/authorized_keys
    sudo chmod 600 /root/.ssh/authorized_keys
    sudo chown root:root /root/.ssh/id_rsa /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    if [ $? -eq 0 ]; then
        log_success "SSH key copied to root's .ssh directory successfully."
    else
        log_fail "Failed to copy SSH key to root."
        exit 1
    fi
fi

read -p "Press enter after you've added the SSH key to GitLab..."

# Step 3: Clone the GitLab repository as root
read -p "Please enter your GitLab repository URL: " gitlab_repo_url

# Extract project name from the GitLab URL
project_name=$(basename -s .git $gitlab_repo_url)

# Check if the repository already exists
if [ -d "/home/$deploy_user/$project_name" ]; then
    log_success "Repository already exists in /home/$deploy_user/$project_name. Skipping clone."
else
    echo -e "${BLUE}Cloning the repository...${NC}"
    sudo git clone $gitlab_repo_url /home/$deploy_user/$project_name
    if [ $? -eq 0 ]; then
        log_success "Repository cloned successfully to /home/$deploy_user/$project_name."
        sudo -u $deploy_user git config --global --add safe.directory /home/$deploy_user/$project_name
        log_success "Git config command executed successfully."
        sudo chown -R $deploy_user:$deploy_user /home/$deploy_user/$project_name
        sudo chmod -R u+rwX /home/$deploy_user/$project_name
        log_success "Permissions fixed successfully."

        # Add SSH key to the agent and configure git
        echo -e "${BLUE}Starting SSH agent and adding the key...${NC}"
        eval $(ssh-agent -s)
        ssh-add /home/$deploy_user/.ssh/id_rsa
        sudo -u $deploy_user bash -c 'eval "$(ssh-agent -s)" && ssh-add /home/'"$deploy_user"'/.ssh/id_rsa'
        if [ $? -eq 0 ]; then
            log_success "SSH key added to the agent."
        else
            log_fail "Failed to add SSH key to the agent."
        fi

    else
        log_fail "Failed to clone the repository."
        exit 1
    fi
fi

# Step 4: Install Docker
if command -v docker &>/dev/null; then
    log_success "Docker is already installed. Skipping Docker installation."
else
    echo -e "${BLUE}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh ./get-docker.sh
    sudo usermod -aG docker $deploy_user
    if [ $? -eq 0 ]; then
        log_success "Docker installed successfully."
    else
        log_fail "Failed to install Docker."
        exit 1
    fi
fi

# Step 5: Install Docker Compose
if command -v docker-compose &>/dev/null; then
    log_success "Docker Compose is already installed. Skipping Docker Compose installation."
else
    echo -e "${BLUE}Installing Docker Compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    if [ $? -eq 0 ]; then
        log_success "Docker Compose installed successfully."
    else
        log_fail "Failed to install Docker Compose."
        exit 1
    fi
fi

# Step 6: Clean up .bash_logout file
if [ -f "/home/$deploy_user/.bash_logout" ]; then
    echo -e "${BLUE}Removing .bash_logout to prevent environment preparation issues...${NC}"
    sudo rm /home/$deploy_user/.bash_logout
    log_success ".bash_logout file has been removed successfully."
fi

# Step 7: Install UFW and configure firewall rules
if sudo ufw status | grep -q "active"; then
    log_success "UFW is already active. Skipping UFW installation and configuration."
else
    echo -e "${BLUE}Installing UFW and configuring firewall...${NC}"
    sudo apt update && sudo apt install -y ufw
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 23232/tcp
    sudo ufw enable
    if [ $? -eq 0 ]; then
        log_success "UFW installed and configured successfully."
    else
        log_fail "Failed to configure UFW."
        exit 1
    fi
fi

# Step 8: Change SSH port to 23232
if grep -q "Port 23232" /etc/ssh/sshd_config; then
    log_success "SSH port is already set to 23232. Skipping this step."
else
    echo -e "${BLUE}Changing SSH port to 23232...${NC}"
    sudo sed -i 's/#Port 22/Port 23232/' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    if [ $? -eq 0 ]; then
        log_success "SSH port changed to 23232 and service restarted."
    else
        log_fail "Failed to change SSH port."
        exit 1
    fi
fi

# Step 9: Install and configure Netdata with basic authentication
if command -v netdata &>/dev/null; then
    log_success "Netdata is already installed. Skipping installation."
else
    echo -e "${BLUE}Installing Netdata...${NC}"
    sudo apt update
    sudo apt install -y netdata
    sudo systemctl enable netdata
    sudo systemctl start netdata
    if [ $? -eq 0 ]; then
        log_success "Netdata installed successfully."
        echo -e "${BLUE}Configuring Netdata with basic authentication...${NC}"
        sudo htpasswd -c /etc/netdata/htpasswd emeax_admin <<< "WGc5WfwkgxXpkrf"
        sudo sed -i '/\[web\]/a mode = multi-threaded\ndefault port = 19999\nauth mode = basic-auth\nauth file = /etc/netdata/htpasswd' /etc/netdata/netdata.conf
        sudo systemctl restart netdata
        if [ $? -eq 0 ]; then
            log_success "Netdata configured with basic authentication successfully."
        else
            log_fail "Failed to configure Netdata authentication."
            exit 1
        fi
    else
        log_fail "Failed to install Netdata."
        exit 1
    fi
fi


# Step 10: Install and configure GitLab Runner
if command -v gitlab-runner &>/dev/null; then
    log_success "GitLab Runner is already installed. Skipping installation."
else
    echo -e "${BLUE}Installing GitLab Runner...${NC}"
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
    log_success "GitLab Runner installed successfully."
fi

if sudo systemctl is-active --quiet gitlab-runner; then
    log_success "GitLab Runner is already running. Skipping this step."
else
    echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
    sudo gitlab-runner install --user=$deploy_user --working-directory=/home/$deploy_user
    sudo gitlab-runner start
    if sudo systemctl is-active --quiet gitlab-runner; then
        log_success "GitLab Runner is running successfully."
    else
        log_fail "GitLab Runner failed to start. Please check the logs for more details."
        exit 1
    fi

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
        log_success "GitLab Runner registered successfully."
    else
        log_fail "Failed to register GitLab Runner."
        exit 1
    fi
    sudo systemctl restart gitlab-runner
fi

# Summary of steps
echo -e "${BLUE}Summary of completed steps:${NC}"
for step in "${SUCCESS_STEPS[@]}"; do
    echo -e "${GREEN}[✓] $step${NC}"
done

if [ ${#FAILED_STEPS[@]} -ne 0 ]; then
    echo -e "${RED}The following steps failed:${NC}"
    for step in "${FAILED_STEPS[@]}"; do
        echo -e "${RED}[✗] $step${NC}"
    done
else
    echo -e "${GREEN}All steps completed successfully.${NC}"
fi
