#!/bin/bash

# رنگ‌های متن برای نمایش بهتر
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Create deployer user if not exists
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
if command -v nginx &>/dev/null; then
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
if [ -f "/home/deployer/.bash_logout" ]; then
    echo -e "${BLUE}Cleaning up .bash_logout to prevent environment preparation issues...${NC}"
    sudo sh -c 'echo "" > /home/deployer/.bash_logout'
    echo -e "${GREEN}.bash_logout file has been cleaned up successfully.${NC}"
fi

# Step 6: Install and configure GitLab Runner
if command -v gitlab-runner &>/dev/null; then
    echo -e "${RED}GitLab Runner is already installed. Skipping installation.${NC}"
else
    echo -e "${BLUE}Installing GitLab Runner...${NC}"
    curl -L --output /tmp/gitlab-runner-linux-amd64 "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
    sudo chmod +x /usr/local/bin/gitlab-runner
    echo -e "${GREEN}GitLab Runner installed successfully.${NC}"
fi

# Stopping GitLab Runner if it's running
echo -e "${BLUE}Stopping GitLab Runner if it's running...${NC}"
sudo gitlab-runner stop

# Ensure old configuration is removed
if [ -f "/etc/gitlab-runner/config.toml" ]; then
    echo -e "${RED}Old config.toml file found. Backing up and removing it...${NC}"
    sudo mv /etc/gitlab-runner/config.toml /etc/gitlab-runner/config.toml.bak
fi

# Install and start GitLab Runner as a service
echo -e "${BLUE}Installing and starting GitLab Runner as a service...${NC}"
sudo gitlab-runner install --user=deployer --working-directory=/home/deployer
sudo gitlab-runner start

# Check GitLab Runner service status
if sudo systemctl is-active --quiet gitlab-runner; then
    echo -e "${GREEN}GitLab Runner is running successfully.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start. Please check the logs for more details.${NC}"
    exit 1
fi

# Register GitLab Runner
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

# Restart GitLab Runner and check service status
sudo systemctl restart gitlab-runner
if sudo systemctl is-active --quiet gitlab-runner; then
    echo -e "${GREEN}GitLab Runner is running and ready to accept jobs.${NC}"
else
    echo -e "${RED}GitLab Runner failed to start after registration. Please check the logs for more details.${NC}"
    exit 1
fi

# Step 8: Ensure deployer user owns the entire /var/www directory and has the necessary permissions
sudo chown -R deployer:deployer /var/www
sudo chmod -R 755 /var/www

echo -e "${GREEN}Permissions have been set for /var/www and all its contents.${NC}"

# Step 9: Install UFW and configure firewall rules
echo -e "${BLUE}Installing UFW and configuring firewall...${NC}"
sudo apt install -y ufw
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 23232/tcp
sudo ufw enable
echo -e "${GREEN}UFW installed and configured successfully.${NC}"

# Step 10: Change SSH port to 23232
echo -e "${BLUE}Changing SSH port to 23232...${NC}"
sudo sed -i 's/#Port 22/Port 23232/' /etc/ssh/sshd_config
sudo systemctl restart ssh
echo -e "${GREEN}SSH port changed to 23232 and service restarted.${NC}"

# Step 11: Get the domain name from the user
echo -e "${BLUE}Please enter your domain name (e.g., example.com):${NC}"
read domain_name

# Step 12: Create SSL certificate for the domain
echo -e "${BLUE}Creating SSL certificate for ${domain_name}...${NC}"
sudo -u deployer bash -c "cat > /var/www/localhost.conf <<EOF
[req]
default_bits       = 2048
default_keyfile    = ${domain_name}.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
countryName                 = Country Name (2 letter code)
countryName_default         = US
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = New York
localityName                = Locality Name (eg, city)
localityName_default        = Rochester
organizationName            = Organization Name (eg, company)
organizationName_default    = ${domain_name}
organizationalUnitName      = organizationalunit
organizationalUnitName_default = Development
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_default          = ${domain_name}
commonName_max              = 64

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = ${domain_name}
DNS.2   = localhost
DNS.3   = 127.0.0.1
EOF"

sudo -u deployer bash -c "cd /var/www && sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${domain_name}.key -out ${domain_name}.crt -config localhost.conf"

echo -e "${GREEN}SSL certificate created and stored in /var/www.${NC}"

# Step 13: Get project type from the user (Static or Dynamic)
echo -e "${BLUE}Is your project Static or Dynamic? (type 'static' or 'dynamic')${NC}"
read project_type

# Step 14: Based on the project type, configure Nginx
if [ "$project_type" == "static" ]; then
    echo -e "${BLUE}Please enter the folder path relative to the repository root (e.g., public):${NC}"
    read folder_path

    echo -e "${BLUE}Configuring Nginx for a static site...${NC}"
    sudo -u deployer bash -c "cat > /var/www/${domain_name}.conf <<EOF
server {
    listen 80;
    server_name ${domain_name} www.${domain_name};

    location / {
        root /var/www/$(basename $repo_url .git)/${folder_path};
        index index.html;
    }

    listen 443 ssl;
    ssl_certificate /var/www/${domain_name}.crt;
    ssl_certificate_key /var/www/${domain_name}.key;
}
EOF"

elif [ "$project_type" == "dynamic" ]; then
    echo -e "${BLUE}Please enter the port your application runs on (e.g., 3000):${NC}"
    read app_port

    echo -e "${BLUE}Configuring Nginx for a dynamic site with reverse proxy...${NC}"
    sudo -u deployer bash -c "cat > /var/www/${domain_name}.conf <<EOF
server {
    listen 80;
    server_name ${domain_name} www.${domain_name};

    location / {
        proxy_pass http://localhost:${app_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    listen 443 ssl;
    ssl_certificate /var/www/${domain_name}.crt;
    ssl_certificate_key /var/www/${domain_name}.key;
}
EOF"

else
    echo -e "${RED}Invalid project type entered. Please run the script again and enter 'static' or 'dynamic'.${NC}"
    exit 1
fi

# Step 15: Link the configuration file and restart Nginx
echo -e "${BLUE}Linking the Nginx configuration and restarting the service...${NC}"
sudo ln -s /var/www/${domain_name}.conf /etc/nginx/sites-available/${domain_name}.conf
sudo ln -s /etc/nginx/sites-available/${domain_name}.conf /etc/nginx/sites-enabled/

sudo systemctl restart nginx

# Verify Nginx configuration
if sudo nginx -t; then
    echo -e "${GREEN}Nginx is configured successfully and running.${NC}"
else
    echo -e "${RED}Nginx configuration failed. Please check the configuration file.${NC}"
    exit 1
fi

echo -e "${GREEN}Nginx setup completed! Your site should be accessible at https://${domain_name}.${NC}"
