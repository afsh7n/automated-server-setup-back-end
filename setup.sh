#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Check if SSH Key already exists
if [ -f "~/.ssh/id_rsa" ]; then
    echo "SSH key already exists. Skipping SSH key generation."
else
    echo "Please enter your email address for SSH key generation:"
    read email
    ssh-keygen -t rsa -b 4096 -C "$email" -N "" -f ~/.ssh/id_rsa

    # Display the public key in green color
    echo -e "\e[32mHere is your public SSH key:\e[0m"
    cat ~/.ssh/id_rsa.pub
fi

# Step 2: Install Nginx if not already installed
if command_exists nginx; then
    echo "Nginx is already installed. Skipping Nginx installation."
else
    sudo apt update
    sudo apt install -y nginx
fi

# Step 3: Install NVM if not already installed
if [ -d "$HOME/.nvm" ]; then
    echo "NVM is already installed. Skipping NVM installation."
else
    echo "Which version of NVM would you like to install? (default is latest LTS)"
    read nvm_version

    if [ -z "$nvm_version" ]; then
        nvm_version="lts/*"
    fi

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # Load nvm into the current shell
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    nvm install $nvm_version
fi

# Step 4: Clone the repository if not already present
project_folder="/var/www/$(basename $repo_url .git)"
if [ -d "$project_folder" ]; then
    echo "Project directory already exists. Skipping git clone."
else
    echo "Please enter your GitLab repository URL:"
    read repo_url

    sudo mkdir -p /var/www
    sudo chown $(whoami):$(whoami) /var/www
    cd /var/www

    git clone $repo_url
    cd $(basename $repo_url .git)
    npm install
fi

# Step 5: Create deployer user if not exists
if id "deployer" &>/dev/null; then
    echo "User deployer already exists. Skipping user creation."
else
    echo "Creating deployer user..."
    sudo adduser --disabled-password --gecos "" deployer
    sudo usermod -aG sudo deployer
    sudo mkdir -p /home/deployer/.ssh
    sudo cp ~/.ssh/id_rsa.pub /home/deployer/.ssh/authorized_keys
    sudo chown -R deployer:deployer /home/deployer/.ssh
    sudo chmod 600 /home/deployer/.ssh/authorized_keys
fi

# Step 6: Install GitLab Runner if not already installed
if command_exists gitlab-runner; then
    echo "GitLab Runner is already installed. Skipping installation."
else
    echo "Installing GitLab Runner..."
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
fi

# Step 7: Register GitLab Runner if not already registered
if [ -f "/etc/gitlab-runner/config.toml" ]; then
    echo "GitLab Runner is already registered. Skipping registration."
else
    echo "Please enter your GitLab Runner registration token:"
    read registration_token
    echo "Please enter your GitLab Runner URL (e.g., https://gitlab.com/):"
    read gitlab_url

    sudo gitlab-runner register --non-interactive \
      --url "$gitlab_url" \
      --registration-token "$registration_token" \
      --executor "shell" \
      --description "My GitLab Runner" \
      --tag-list "shell,linux" \
      --run-untagged="true" \
      --locked="false"
fi

# Step 8: Start the GitLab Runner if not already running
if sudo systemctl is-active --quiet gitlab-runner; then
    echo "GitLab Runner is already running."
else
    sudo gitlab-runner start
    echo -e "\e[32mGitLab Runner has been successfully installed, registered, and started!\e[0m"
fi
