#!/bin/bash

# Ultimate WebDAV Setup Script for Debian (Fixed: Suppress FQDN Warning + Robust Tests)
# Author: Grok (xAI) - Secure, idempotent, full-CRUD

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

echo -e "${GREEN}=== Ultimate WebDAV Server Setup (Fixed) ===${NC}"
echo "Sets up secure WebDAV with full local/WebDAV writes, Windows support, and no warnings."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prompt function with default
prompt_default() {
    local prompt="$1"
    local default="$2"
    read -p "$prompt (default: $default): " value
    echo "${value:-$default}"
}

# Prompts
PORT=$(prompt_default "Enter port" "80")
AUTH_USER=$(prompt_default "Enter auth username" "$(whoami)")
SHARE_PATH=$(prompt_default "Enter share directory" "/home/$(whoami)/")

# Safety check for home dir share
if [[ "$SHARE_PATH" == "/home/$AUTH_USER/"* ]]; then
    echo -e "${YELLOW}Warning: Sharing home dir ($SHARE_PATH) exposes sensitive files.${NC}"
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Ensure path exists
if [[ ! -d "$SHARE_PATH" ]]; then
    echo -e "${RED}Error: Directory $SHARE_PATH does not exist. Creating it...${NC}"
    sudo mkdir -p "$SHARE_PATH"
    sudo chown "$AUTH_USER:$AUTH_USER" "$SHARE_PATH"
fi

echo -e "${GREEN}Starting installation...${NC}"

# 1. Update and install Apache if not present
if ! command_exists apache2; then
    echo "Installing Apache2..."
    sudo apt update
    sudo apt install -y apache2 apache2-utils
else
    echo "Apache2 already installed."
fi

# 2. Suppress FQDN warning globally (idempotent)
APACHE_CONF="/etc/apache2/apache2.conf"
if ! grep -q "^ServerName " "$APACHE_CONF"; then
    echo "ServerName localhost" | sudo tee -a "$APACHE_CONF" > /dev/null
    echo "Added global ServerName to suppress FQDN warning."
fi

# 3. Enable modules (idempotent)
sudo a2enmod dav dav_fs auth_basic

# 4. Create/update password file
PASSWD_FILE="/etc/apache2/dav.passwd"
if [[ ! -f "$PASSWD_FILE" ]]; then
    echo "Setting up authentication for user: $AUTH_USER"
    sudo htpasswd -c "$PASSWD_FILE" "$AUTH_USER"
else
    echo "Updating password for $AUTH_USER..."
    sudo htpasswd "$PASSWD_FILE" "$AUTH_USER"
fi
sudo chown www-data:www-data "$PASSWD_FILE"
sudo chmod 640 "$PASSWD_FILE"

# 5. Configure site (idempotent: overwrite if exists)
CONFIG_FILE="/etc/apache2/sites-available/webdav.conf"
sudo tee "$CONFIG_FILE" > /dev/null <<EOT
<VirtualHost *:${PORT}>
    ServerName localhost
    DocumentRoot $SHARE_PATH

    <Directory $SHARE_PATH>
        Options Indexes MultiViews
        AllowOverride None

        # WebDAV core
        DAV On

        # Strict Basic auth (no anon access)
        AuthType Basic
        AuthName "WebDAV Login"
        AuthUserFile $PASSWD_FILE
        Require valid-user
    </Directory>

    # Lock database for Windows/concurrency support
    DAVLockDB /var/lock/apache2/davlocks

    ErrorLog \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOT

# 6. Enable site, disable default if conflicting
sudo a2ensite webdav.conf 2>/dev/null || echo "Site already enabled."
if sudo a2query -s 000-default | grep -q enabled; then
    sudo a2dissite 000-default
fi

# 7. Add Listen directive if missing
PORTS_CONF="/etc/apache2/ports.conf"
if ! grep -q "Listen ${PORT}" "$PORTS_CONF"; then
    echo "Listen ${PORT}" | sudo tee -a "$PORTS_CONF" > /dev/null
fi

# 8. Permissions: Owner www-data, group $AUTH_USER, 775 for full rwx
sudo chown -R www-data:"$AUTH_USER" "$SHARE_PATH"
sudo chmod -R 775 "$SHARE_PATH"

# 9. Lock DB setup
LOCK_DIR="/var/lock/apache2"
sudo mkdir -p "$LOCK_DIR"
sudo touch "$LOCK_DIR/davlocks"
sudo chown www-data:www-data "$LOCK_DIR/davlocks"
sudo chmod 660 "$LOCK_DIR/davlocks"

# 10. Firewall (ufw if present)
if command_exists ufw; then
    echo "Configuring firewall..."
    sudo ufw allow "${PORT}/tcp" 2>/dev/null || echo "Port ${PORT} already allowed."
    sudo ufw reload
fi

# 11. Restart and enable service
sudo service apache2 restart
sudo update-rc.d apache2 defaults 2>/dev/null || echo "Already enabled on boot."

# 12. Improved tests (filter warnings, check for Syntax OK)
echo -e "${GREEN}Running tests...${NC}"
CONFIG_TEST=$(sudo apache2ctl configtest 2>&1 | grep -F "Syntax OK" || true)
if [[ -n "$CONFIG_TEST" ]]; then
    echo -e "${GREEN}Config: OK${NC}"
else
    echo -e "${RED}Config error - check /var/log/apache2/error.log!${NC}"
    exit 1
fi

sudo service apache2 status | head -n 3

# Quick auth test suggestion
echo -e "${YELLOW}Test auth: curl -u $AUTH_USER:'your-password' http://localhost:${PORT}/${NC}"
echo "Local write test: touch $SHARE_PATH/test.txt && rm $SHARE_PATH/test.txt"

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo "Access: http://localhost:${PORT}/ (or VM IP:${PORT})"
echo "Mount in Windows: Map to http://<ip>:${PORT}/ with '$AUTH_USER'"
echo "Logs: tail -f /var/log/apache2/webdav_error.log"
echo "Revert: sudo chown -R $AUTH_USER:$AUTH_USER $SHARE_PATH && sudo chmod -R 755 $SHARE_PATH"