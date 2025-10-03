#!/bin/bash

# Prompt for port (default 80)
read -p "Enter port (default 80): " PORT
PORT=${PORT:-80}

# Prompt for username (default current user)
USERNAME=$(whoami)
read -p "Enter username for authentication (default $USERNAME): " AUTH_USER
AUTH_USER=${AUTH_USER:-$USERNAME}

# Prompt for share path (default /home/$AUTH_USER/)
DEFAULT_PATH="/home/$AUTH_USER/"
read -p "Enter directory to share (default $DEFAULT_PATH): " SHARE_PATH
SHARE_PATH=${SHARE_PATH:-$DEFAULT_PATH}

# Update and install Apache
sudo apt update
sudo apt install apache2 apache2-utils -y

# Restart Apache early to ensure it's running
sudo service apache2 restart

# Enable WebDAV modules
sudo a2enmod dav
sudo a2enmod dav_fs

# Create password file (will prompt for password)
sudo htpasswd -c /etc/apache2/dav.passwd "$AUTH_USER"

# Fix password file permissions for Apache to read
sudo chown www-data:www-data /etc/apache2/dav.passwd
sudo chmod 640 /etc/apache2/dav.passwd

# Create webdav.conf (uses provided port, user, and path; NO Require all granted)
sudo tee /etc/apache2/sites-available/webdav.conf > /dev/null <<EOT
<VirtualHost *:${PORT}>
    ServerName localhost
    DocumentRoot ${SHARE_PATH}

    <Directory ${SHARE_PATH}>
        Options Indexes MultiViews
        AllowOverride None

        # WebDAV settings
        DAV On

        # Basic authentication
        AuthType Basic
        AuthName "WebDAV Login"
        AuthUserFile /etc/apache2/dav.passwd
        Require valid-user
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOT

# Enable site, disable default
sudo a2ensite webdav.conf
sudo a2dissite 000-default.conf

# Adjust permissions on share path (allows Apache rwx as owner)
sudo chown -R www-data:"$AUTH_USER" "$SHARE_PATH"
sudo chmod -R 755 "$SHARE_PATH"

# Add Listen to ports.conf (if not already there)
if ! grep -q "Listen ${PORT}" /etc/apache2/ports.conf; then
    echo "Listen ${PORT}" | sudo tee -a /etc/apache2/ports.conf > /dev/null
fi

# Restart Apache and enable on boot
sudo service apache2 restart
sudo update-rc.d apache2 defaults

# Quick syntax test and status
sudo apache2ctl configtest
sudo service apache2 status