#!/usr/bin/env bash
# Repair "Access denied for user 'demo'@'localhost'" on the ACTIVE node.
#   sudo ./fix-db-user.sh
# Re-syncs the MySQL 'demo' user with the password stored in
# /mnt/shared/app/app.env, and makes sure the database and table exist.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
ENV=/mnt/shared/app/app.env

mountpoint -q /mnt/shared   || { echo "Shared disk not mounted – run ./activate.sh first"; exit 1; }
mountpoint -q /var/lib/mysql || { echo "/var/lib/mysql is not the shared disk – run ./activate.sh first"; exit 1; }
[[ -f "$ENV" ]] || { echo "$ENV missing"; exit 1; }

# shellcheck disable=SC1090
source "$ENV"

echo ">> Datadir in use: $(mysql -Nse 'SELECT @@datadir')"

mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
CREATE TABLE IF NOT EXISTS ${DB_NAME}.notes (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message    VARCHAR(500) NOT NULL,
  written_by VARCHAR(64)  NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

systemctl restart demo-app
echo ">> Notes in DB: $(mysql -Nse "SELECT COUNT(*) FROM ${DB_NAME}.notes")"
echo ">> Health: $(curl -s localhost/health)"
