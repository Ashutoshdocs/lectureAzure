#!/bin/bash

# ==============================
# VARIABLES
# ==============================
MYSQL_USER="demouser"
MYSQL_PASS="Pass@12345"
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"

echo "=============================="
echo " MySQL Installation Script"
echo "=============================="

# ==============================
# INSTALL MYSQL
# ==============================
echo "[1/6] Updating system..."
sudo apt update -y

echo "[2/6] Installing MySQL Server..."
sudo apt install mysql-server -y

# ==============================
# START MYSQL
# ==============================
echo "[3/6] Starting and enabling MySQL..."
sudo systemctl start mysql
sudo systemctl enable mysql

# ==============================
# ENABLE REMOTE ACCESS
# ==============================
echo "[4/6] Enabling MySQL remote access..."

sudo sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" $MYSQL_CONF

# ==============================
# CREATE USER & GRANT PRIVILEGES
# ==============================
echo "[5/6] Creating MySQL user and granting full access..."

sudo mysql <<EOF
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# ==============================
# RESTART MYSQL
# ==============================
echo "[6/6] Restarting MySQL service..."
sudo systemctl restart mysql

# ==============================
# STATUS CHECK
# ==============================
echo "Checking MySQL status..."
sudo systemctl status mysql --no-pager

# ==============================
# SECURITY WARNING
# ==============================
echo "===================================================="
echo "⚠️  SECURITY WARNING"
echo "===================================================="
echo "- MySQL allows remote access from ANY host (%)"
echo "- User has FULL privileges on ALL databases"
echo "- Password is hardcoded in the script"
echo ""
echo "❌ DO NOT use this configuration in PRODUCTION"
echo "✅ Intended ONLY for labs, demos, CI/CD, learning"
echo "===================================================="

echo "MySQL setup completed successfully."

