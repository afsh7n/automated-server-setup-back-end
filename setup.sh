#!/bin/bash

# رنگ‌های متن برای نمایش بهتر
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Check if SSH Key already exists
if [ -f "~/.ssh/id_rsa" ]; then
    echo -e "${RED}SSH key already exists. Skipping SSH key generation.${NC}"
else
    echo -e "${BLUE}Please enter your email address for SSH key generation:${NC}"
    read email
    ssh-keygen -t rsa -b 4096 -C "$email" -N "" -f ~/.ssh/id_rsa

    # Display the public key in green color
    echo -e "${GREEN}Here is your public SSH key:${NC}"
    cat ~/.ssh/id_rsa.pub

    echo -e "${BLUE}To add this SSH key to your GitLab repository, follow these steps:${NC}"
    echo -e "${BLUE}1. Copy the above public SSH key.${NC}"
    echo -e "${BLUE}2. Go to your GitLab repository page.${NC}"
    echo -e "${BLUE}3. Click on 'Settings' from the left sidebar.${NC}"
    echo -e "${BLUE}4. Under 'Repository', click on 'Deploy Keys'.${NC}"
    echo -e "${BLUE}5. Click 'Add deploy key', paste the SSH key, give it a title, and click 'Add key'.${NC}"
fi

# Step 2: Install Nginx if not already installed
if command_exists nginx; then
    echo -e "${RED}Nginx is already installed. Skipping Nginx installation.${NC}"
else
    echo -e "${BLUE}Installing Nginx...${NC}"
    sudo apt update
    sudo apt install -y nginx
    echo -e "${GREEN}Nginx installed successfully.${NC}"
fi

# Step 3: Install NVM if not already installed
if [ -d "$HOME/.nvm" ]; then
    echo -e "${RED}NVM is already installed. Skipping NVM installation.${NC}"
else
    echo -e "${BLUE}Which version of NVM would you like to install? (default is latest LTS)${NC}"
    read nvm_version

    if [ -z "$nvm_version" ]; then
        nvm_version="lts/*"
    fi

    echo -e "${BLUE}Installing NVM version $nvm_version...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # Load nvm into the current shell
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    nvm install $nvm_version
    echo -e "${GREEN}NVM installed successfully.${NC}"
fi

# Step 4: Clone the repository if not already present
if [ -z "$project_folder" ]; then
    echo -e "${BLUE}Please enter your GitLab repository URL:${NC}"
    read repo_url

    project_folder="/var/www/$(basename $repo_url .git)"
fi

if [ -d "$project_folder" ]; then
    echo -e "${RED}Project directory already exists. Skipping git clone.${NC}"
else
    echo -e "${BLUE}Cloning the repository...${NC}"
    sudo mkdir -p /var/www
    sudo chown $(whoami):$(whoami) /var/www
    cd /var/www

    git clone $repo_url
    cd $(basename $repo_url .git)
    npm install
    echo -e "${GREEN}Repository cloned and npm packages installed successfully.${NC}"
fi

# Step 5: Create deployer user if not exists
if id "deployer" &>/dev/null; then
    echo -e "${RED}User deployer already exists. Skipping user creation.${NC}"
else
    echo -e "${BLUE}Creating deployer user...${NC}"
    sudo adduser --disabled-password --gecos "" deployer
    sudo usermod -aG sudo deployer
    sudo mkdir -p /home/deployer/.ssh
    sudo cp ~/.ssh/id_rsa.pub /home/deployer/.ssh/authorized_keys
    sudo chown -R deployer:deployer /home/deployer/.ssh
    sudo chmod 600 /home/deployer/.ssh/authorized_keys
    echo -e "${GREEN}User deployer created and configured successfully.${NC}"
fi

# Step 6: Install and configure GitLab Runner
if command_exists gitlab-runner; then
    echo -e "${RED}GitLab Runner is already installed. Skipping installation.${NC}"
else
    echo -e "${BLUE}Installing GitLab Runner...${NC}"
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
    echo -e "${GREEN}GitLab Runner installed successfully.${NC}"
fi

# توقف GitLab Runner در صورت در حال اجرا بودن
echo -e "${BLUE}Stopping GitLab Runner if it's running...${NC}"
sudo gitlab-runner stop

# اطمینان از پاک بودن فایل پیکربندی قدیمی
if [ -f "/etc/gitlab-runner/config.toml" ]; then
    echo -e "${RED}Old config.toml file found. Backing up and removing it...${NC}"
    sudo mv /etc/gitlab-runner/config.toml /etc/gitlab-runner/config.toml.bak
fi

# نصب و راه‌اندازی GitLab Runner به عنوان سرویس
echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
sudo gitlab-runner install --user=deployer --working-directory=/home/deployer
sudo gitlab-runner start

# بررسی وضعیت سرویس
if sudo systemctl is-active --quiet gitlab-runner
then
    echo -e "${GREEN}GitLab Runner is running successfully.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start. Please check the logs for more details.${NC}"
    exit 1
fi

# ثبت‌نام GitLab Runner
echo -e "${BLUE}Registering GitLab Runner...${NC}"
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

# بررسی مجدد وضعیت سرویس
sudo systemctl restart gitlab-runner
if sudo systemctl is-active --quiet gitlab-runner
then
    echo -e "${GREEN}GitLab Runner is running and ready to accept jobs.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start after registration. Please check the logs for more details.${NC}"
    exit 1
fi

echo -e "${GREEN}Setup completed successfully!${NC}"
