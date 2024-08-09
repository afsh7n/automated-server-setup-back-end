#!/bin/bash

# رنگ‌های متن برای نمایش بهتر
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Create deployer user if not exists (this step is crucial)
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

# Step 2: Install Nginx if not already installed
if command_exists nginx; then
    echo -e "${RED}Nginx is already installed. Skipping Nginx installation.${NC}"
else
    echo -e "${BLUE}Installing Nginx...${NC}"
    sudo apt update
    sudo apt install -y nginx
    echo -e "${GREEN}Nginx installed successfully.${NC}"
fi

# Step 3: Install NVM for the deployer user and Node.js
if sudo -u deployer test -d "/home/deployer/.nvm"; then
    echo -e "${RED}NVM is already installed for deployer. Skipping NVM installation.${NC}"
else
    echo -e "${BLUE}Installing NVM for deployer...${NC}"
    sudo -u deployer -H bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash"
    sudo -u deployer -H bash -c "export NVM_DIR=\"/home/deployer/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\" && nvm install --lts"
    echo -e "${GREEN}NVM and Node.js installed successfully for deployer.${NC}"
fi

# Ensure NVM is loaded in the deployer user's environment
sudo -u deployer -H bash -c "export NVM_DIR=\"/home/deployer/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\" && nvm use --lts"

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
    sudo -u deployer -H bash -c "cd /var/www/$(basename $repo_url .git) && npm install"
    echo -e "${GREEN}Repository cloned and npm packages installed successfully.${NC}"
fi

# Step 5: Clean up .bash_logout file
if [ -f "/home/deployer/.bash_logout" ];then
    echo -e "${BLUE}Cleaning up .bash_logout to prevent environment preparation issues...${NC}"
    sudo sh -c 'echo "" > /home/deployer/.bash_logout'
    echo -e "${GREEN}.bash_logout file has been cleaned up successfully.${NC}"
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
if [ -f "/etc/gitlab-runner/config.toml" ];then
    echo -e "${RED}Old config.toml file found. Backing up and removing it...${NC}"
    sudo mv /etc/gitlab-runner/config.toml /etc/gitlab-runner/config.toml.bak
fi

# نصب و راه‌اندازی GitLab Runner به عنوان سرویس
echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
sudo gitlab-runner install --user=deployer --working-directory=/home/deployer
sudo gitlab-runner start

# بررسی وضعیت سرویس
if sudo systemctl is-active --quiet gitlab-runner;then
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

if [ $? -eq 0 ];then
    echo -e "${GREEN}GitLab Runner registered successfully.${NC}"
else
    echo -e "${RED}Failed to register GitLab Runner. Please check the provided token and try again.${NC}"
    exit 1
fi

# بررسی مجدد وضعیت سرویس
sudo systemctl restart gitlab-runner
if sudo systemctl is-active --quiet gitlab-runner;then
    echo -e "${GREEN}GitLab Runner is running and ready to accept jobs.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start after registration. Please check the logs for more details.${NC}"
    exit 1
fi

echo -e "${GREEN}Setup completed successfully!${NC}"
