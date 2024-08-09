#!/bin/bash

# Step 1: Generate SSH Key
echo "Please enter your email address for SSH key generation:"
read email
ssh-keygen -t rsa -b 4096 -C "$email" -N "" -f ~/.ssh/id_rsa

# Display the public key in green color
echo -e "\e[32mHere is your public SSH key:\e[0m"
cat ~/.ssh/id_rsa.pub

# Step 2: Install Nginx and NVM
sudo apt update
sudo apt install -y nginx

# Install NVM
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

# Step 3: Clone the repository
echo "Please enter your GitLab repository URL:"
read repo_url

sudo mkdir -p /var/www
sudo chown $(whoami):$(whoami) /var/www
cd /var/www

git clone $repo_url

# Get the project folder name from the repo URL
project_folder=$(basename $repo_url .git)

cd $project_folder

# Step 4: Install project dependencies using npm
npm install

# Step 5: Create deployer user
echo "Creating deployer user..."
sudo adduser --disabled-password --gecos "" deployer
sudo usermod -aG sudo deployer
sudo mkdir -p /home/deployer/.ssh
sudo cp ~/.ssh/id_rsa.pub /home/deployer/.ssh/authorized_keys
sudo chown -R deployer:deployer /home/deployer/.ssh
sudo chmod 600 /home/deployer/.ssh/authorized_keys

# Step 6: Install GitLab Runner
echo "Installing GitLab Runner..."
curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner

# Register GitLab Runner
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
  --locked="false" \
  --user="deployer"

# Configure GitLab Runner to run as the deployer user
sudo gitlab-runner install --user=deployer --working-directory=/home/deployer

# Start the GitLab Runner
sudo gitlab-runner start

echo -e "\e[32mGitLab Runner has been successfully installed and configured!\e[0m"
