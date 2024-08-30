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

# Step 7: Ensure deployer user owns the entire /var/www directory and has the necessary permissions
sudo chown -R deployer:deployer /var/www
sudo chmod -R 755 /var/www

echo -e "${GREEN}Permissions have been set for /var/www and all its contents.${NC}"

# Step 8: Install UFW and configure firewall rules
echo -e "${BLUE}Installing UFW and configuring firewall...${NC}"
sudo apt install -y ufw
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 23232/tcp
sudo ufw enable
echo -e "${GREEN}UFW installed and configured successfully.${NC}"

# Step 9: Change SSH port to 23232
echo -e "${BLUE}Changing SSH port to 23232...${NC}"
sudo sed -i 's/#Port 22/Port 23232/' /etc/ssh/sshd_config
sudo systemctl restart ssh
echo -e "${GREEN}SSH port changed to 23232 and service restarted.${NC}"

# Step 10: Get the domain name from the user
echo -e "${BLUE}Please enter your domain name (e.g., example.com):${NC}"
read domain_name

# Step 11: Create SSL certificate for the domain
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
commonName                  = Common Name (eg, fully qualified host name)
commonName_default          = ${domain_name}
commonName_max              = 64
emailAddress                = Email Address
emailAddress_default        = admin@${domain_name}
emailAddress_max            = 64

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
basicConstraints = CA:TRUE
keyUsage = cRLSign, keyCertSign

[alt_names]
DNS.1 = ${domain_name}
EOF"

sudo openssl req -new -x509 -nodes -key /var/www/${domain_name}.key -out /var/www/${domain_name}.crt -days 365 -config /var/www/localhost.conf
echo -e "${GREEN}SSL certificate created successfully.${NC}"

# Step 12: Configure Nginx for SSL
echo -e "${BLUE}Configuring Nginx for SSL...${NC}"
sudo bash -c "cat > /etc/nginx/sites-available/${domain_name} <<EOF
server {
    listen 80;
    server_name ${domain_name};

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name ${domain_name};

    ssl_certificate /var/www/${domain_name}.crt;
    ssl_certificate_key /var/www/${domain_name}.key;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF"

# Link and test Nginx configuration
sudo ln -s /etc/nginx/sites-available/${domain_name} /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
echo -e "${GREEN}Nginx configured successfully for SSL.${NC}"

# Step 13: Setup MySQL if Backend
if [ "$project_category" == "backend" ]; then
    if command -v mysql &>/dev/null; then
        echo -e "${RED}MySQL is already installed. Skipping MySQL installation.${NC}"
    else
        echo -e "${BLUE}Installing MySQL...${NC}"
        sudo apt update
        sudo apt install -y mysql-server
        echo -e "${GREEN}MySQL installed successfully.${NC}"
    fi

    # Set up MySQL database and user
    echo -e "${BLUE}Please enter the MySQL root password:${NC}"
    read -s root_password

    echo -e "${BLUE}Please enter the new database name:${NC}"
    read db_name

    echo -e "${BLUE}Please enter the new MySQL username:${NC}"
    read db_user

    echo -e "${BLUE}Please enter the new MySQL user password:${NC}"
    read -s db_password

    echo -e "${BLUE}Creating MySQL database and user...${NC}"
    mysql -u root -p$root_password -e "CREATE DATABASE $db_name;"
    mysql -u root -p$root_password -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';"
    mysql -u root -p$root_password -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
    mysql -u root -p$root_password -e "FLUSH PRIVILEGES;"
    echo -e "${GREEN}MySQL database and user created successfully.${NC}"

    # Create backup script
    backup_script="/usr/local/bin/mysql_backup.sh"

    echo -e "${BLUE}Creating MySQL backup script...${NC}"
    sudo bash -c "cat > $backup_script <<EOF
#!/bin/bash

# رنگ‌های متن برای نمایش بهتر
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# دریافت اطلاعات FTP
echo -e \"\${BLUE}Please enter the FTP host:\${NC}\"
read ftp_host

echo -e \"\${BLUE}Please enter the FTP username:\${NC}\"
read ftp_user

echo -e \"\${BLUE}Please enter the FTP password:\${NC}\"
read -s ftp_password

echo -e \"\${BLUE}Please enter the FTP target directory (e.g., /backups/):\${NC}\"
read ftp_directory

# تاریخ فعلی برای نام فایل بک‌آپ
backup_date=\$(date +%Y-%m-%d_%H-%M-%S)
backup_file=\"/tmp/${db_name}_backup_\${backup_date}.sql\"

# گرفتن بک‌آپ از دیتابیس
echo -e \"\${BLUE}Creating MySQL backup...\${NC}\"
mysqldump -u $db_user -p$db_password $db_name > \$backup_file

if [ \$? -eq 0 ]; then
    echo -e \"\${GREEN}Backup created successfully at \$backup_file.\${NC}\"
else
    echo -e \"\${RED}Failed to create backup. Please check MySQL credentials and database name.\${NC}\"
    exit 1
fi

# انتقال فایل بک‌آپ به سرور FTP
echo -e \"\${BLUE}Transferring backup to FTP server...\${NC}\"
curl -T \$backup_file ftp://\$ftp_user:\$ftp_password@\$ftp_host\$ftp_directory --ftp-create-dirs

if [ \$? -eq 0 ]; then
    echo -e \"\${GREEN}Backup successfully transferred to FTP server.\${NC}\"
    rm \$backup_file  # حذف فایل بک‌آپ بعد از انتقال موفقیت‌آمیز
else
    echo -e \"\${RED}Failed to transfer backup to FTP server. Please check FTP credentials and server availability.\${NC}\"
    exit 1
fi

echo -e \"\${GREEN}Backup and transfer process completed successfully.\${NC}\"
EOF"

    # Set execute permissions for the backup script
    sudo chmod +x $backup_script
    echo -e "${GREEN}Backup script created and executable permissions set.${NC}"

    # Add the backup script to cron for daily execution at 12:00 AM
    echo -e "${BLUE}Adding backup script to cron...${NC}"
    (sudo crontab -l 2>/dev/null; echo "0 0 * * * $backup_script") | sudo crontab -
    echo -e "${GREEN}Backup script added to cron successfully.${NC}"
else
    echo -e "${GREEN}No additional setup required for Frontend project.${NC}"
fi

# Continue with any remaining setup tasks...
# ...

echo -e "${GREEN}Setup completed successfully!${NC}"
