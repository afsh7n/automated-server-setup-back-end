
# DevOps Setup Script

This script automates the process of setting up a server for deployment, including setting up a deployer user, installing necessary software, configuring firewalls, and setting up an Nginx server with SSL for your project.

## How to Use

You can run the script directly from your terminal by using the following command:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/afsh7n/emeax-desain-devops/main/setup.sh)
```

## What Does This Script Do?

### 1. Create `deployer` User
- Checks if a user named `deployer` exists. If not, it creates the user, adds them to the sudo group, and sets up SSH access.

### 2. Install Nginx
- Installs Nginx if it is not already installed on the server.

### 3. Install NVM and Node.js
- Installs NVM (Node Version Manager) and the latest LTS version of Node.js for the `deployer` user.

### 4. Clone Your Git Repository
- Clones a Git repository from GitLab to `/var/www/`.
- You will need to provide the repository URL during the script execution.

### 5. Clean `.bash_logout`
- Cleans the `.bash_logout` file for the `deployer` user to prevent environment preparation issues.

### 6. Install and Configure GitLab Runner
- Installs GitLab Runner and sets it up to run as a service.
- You will need to provide a GitLab Runner registration token during the script execution.

### 7. Install and Configure UFW (Uncomplicated Firewall)
- Installs UFW and opens ports 80, 443, and 23232.
- Changes the default SSH port from 22 to 23232 and restarts the SSH service.

### 8. Generate SSL Certificates
- Prompts you for a domain name and generates a self-signed SSL certificate for that domain.

### 9. Configure Nginx
- Configures Nginx based on the type of project (static or dynamic).
- If static, you will need to provide the folder path relative to the repository root.
- If dynamic, you will need to provide the port on which your application runs.

### 10. Start Nginx
- Applies the Nginx configuration and restarts the Nginx service.

## Input Data Required

- **Repository URL**: URL of the GitLab repository you wish to clone.
- **GitLab Runner Registration Token**: Token to register the GitLab Runner with your GitLab instance.
- **Domain Name**: The domain name for which you want to create the SSL certificate.
- **Project Type**: Whether your project is static or dynamic.
  - If static: The folder path where your static files are located.
  - If dynamic: The port number on which your application is running.

## Benefits of Using This Script

- **Automation**: Automates the entire server setup process, saving you time and reducing the potential for human error.
- **Consistency**: Ensures that all servers are set up in a consistent manner, following best practices.
- **Security**: Configures firewalls and changes the SSH port to enhance security.
- **Flexibility**: Supports both static and dynamic project setups with Nginx.

## Notes

- This script is intended for use on a fresh server setup. Running it on a server with existing configurations may cause conflicts.
- The script is interactive, meaning it will prompt you for the necessary information during execution.

## Conclusion

By using this script, you can quickly and efficiently set up a server for deployment, complete with a secure Nginx setup, GitLab CI/CD integration, and a deployer user for managing your deployments. This reduces the manual effort involved in server setup and ensures a standardized environment for your applications.

