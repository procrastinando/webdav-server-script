#!/bin/bash

# Prompt for port (default 80)
read -p "Enter port (default 80): " PORT
PORT=${PORT:-80}

# Prompt for domain/ServerName (default localhost)
read -p "Enter domain/ServerName (default localhost): " DOMAIN
DOMAIN=${DOMAIN:-localhost}

# Prompt for username (default current user)
USERNAME=$(whoami)
read -p "Enter username for authentication (default $USERNAME): " AUTH_USER
AUTH_USER=${AUTH_USER:-$USERNAME}

# Prompt for share path (default /home/$AUTH_USER/)
DEFAULT_PATH="/home/$AUTH_USER/"
read -p "Enter directory to share (default $DEFAULT_PATH): " SHARE_PATH
SHARE_PATH=${SHARE_PATH:-$DEFAULT_PATH}

# Update and install Apache + modules
sudo apt update
sudo apt install apache2 apache2-utils -y
sudo a2enmod dav dav_fs auth_digest

# Restart Apache early
sudo service apache2 restart

# Create digest password file (will prompt for password)
sudo htdigest -c /etc/apache2/dav.passwd.dig "$DOMAIN" "$AUTH_USER"

# Fix password file permissions
sudo chown www-data:www-data /etc/apache2/dav.passwd.dig
sudo chmod 640 /etc/apache2/dav.passwd.dig

# Create webdav.conf (Digest auth, lock DB, Windows-compatible)
sudo tee /etc/apache2/sites-available/webdav.conf > /dev/null <<EOT
<VirtualHost *:${PORT}>
    ServerName ${DOMAIN}
    DocumentRoot ${SHARE_PATH}

    <Directory ${SHARE_PATH}>
        Options Indexes MultiViews
        AllowOverride None

        # WebDAV settings
        DAV On

        # Digest authentication (Windows-compatible over HTTP)
        AuthType Digest
        AuthName "WebDAV Login"
        AuthDigestDomain /
        AuthUserFile /etc/apache2/dav.passwd.dig
        Require valid-user
    </Directory>

    # WebDAV lock database (required for Windows writes)
    DAVLockDB /var/lock/apache2/davlocks

    ErrorLog \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOT

# Enable site, disable default
sudo a2ensite webdav.conf
sudo a2dissite 000-default.conf

# Set up lock DB
sudo mkdir -p /var/lock/apache2
sudo touch /var/lock/apache2/davlocks
sudo chown www-data:www-data /var/lock/apache2/davlocks
sudo chmod 660 /var/lock/apache2/davlocks

# Adjust permissions on share path (775 for group write)
sudo chown -R www-data:"$AUTH_USER" "$SHARE_PATH"
sudo chmod -R 775 "$SHARE_PATH"

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

echo "Setup complete! Mount with: http://${DOMAIN}:${PORT}/ (use @${PORT} for non-80 ports in Windows)"