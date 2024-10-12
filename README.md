
# Server Setup Automation Script

This Bash script automates the process of setting up a Linux server for deployment. It includes user management, SSH key generation, repository cloning, Docker and Docker Compose installation, firewall configuration, and GitLab Runner setup. The script is designed to simplify the setup process for deploying applications on a new server.

## Features

- Creates a deploy user with sudo privileges.
- Generates SSH keys for both the deploy user and root user.
- Clones a GitLab repository and sets up the Git configuration.
- Installs Docker and Docker Compose.
- Configures UFW firewall rules for HTTP, HTTPS, and SSH access.
- Changes the default SSH port for added security.
- Installs and registers GitLab Runner for CI/CD integration.

## How to Use

### Step 1: Run the Script

To use the script, you can either download it directly or run it from a remote URL. Use the following command to run the script:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/afsh7n/emeax-desain-devops/main/setup.sh)
```

### Step 2: Provide Input During Execution

During script execution, you'll be prompted for the following inputs:

1. **Deploy User**: You can specify a custom username for the deploy user (default is `deployer`).
2. **GitLab Repository URL**: You'll need to provide the SSH URL of your GitLab repository (e.g., `git@gitlab.com:yourusername/yourrepository.git`).
3. **GitLab Runner Registration Token**: When setting up GitLab Runner, you'll be prompted to provide the registration token, which can be found in your GitLab project's settings.

### Script Breakdown

#### 1. **User Creation**
The script checks if the specified deploy user exists. If not, it creates the user with sudo privileges.

#### 2. **SSH Key Generation**
If SSH keys don't exist for the deploy user, the script generates them. You'll need to add the generated public key to your GitLab account to allow the server to clone private repositories.

#### 3. **Cloning the GitLab Repository**
The script clones your specified GitLab repository into the `/home/deployer/` directory. It also configures the repository to be safe for Git operations.

#### 4. **Docker Installation**
The script checks if Docker is installed. If not, it installs Docker and adds the deploy user to the Docker group.

#### 5. **Docker Compose Installation**
The script checks if Docker Compose is installed. If not, it installs Docker Compose from the latest release.

#### 6. **UFW Firewall Configuration**
The script installs and configures UFW (Uncomplicated Firewall) to allow traffic on HTTP (port 80), HTTPS (port 443), and a custom SSH port (23232).

#### 7. **SSH Port Change**
For additional security, the script changes the default SSH port from `22` to `23232`.

#### 8. **GitLab Runner Installation and Configuration**
If GitLab Runner is not installed, the script installs it and registers it with your GitLab project using the registration token. After registration, it ensures that the runner is properly running.

### Troubleshooting

- **Permission Issues**: If you run into permission issues during `git pull` or file access, ensure that the deploy user has the correct ownership of the project directory.
  
  ```bash
  sudo chown -R deployer:deployer /home/deployer/your-repository
  ```

- **Firewall Configuration**: Ensure that your firewall rules are correctly applied, and check the status of UFW with:

  ```bash
  sudo ufw status
  ```

### Conclusion

This script automates the essential setup tasks for deploying an application on a Linux server. By following the steps in this guide, you can easily configure your server with a deploy user, SSH keys, Docker, and GitLab Runner. If you encounter any issues, consult the logs or check the individual components (Docker, GitLab Runner, etc.).

For further support, refer to the project documentation or contact support.
