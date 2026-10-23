#!/usr/bin/env bash
# STEP 5 – run ONCE, on vm01 ONLY:  sudo ./04-init-shared-disk.sh
# Partitions + formats the shared disk, moves MySQL data onto it, copies the
# frontend app onto it, then activates vm01 and creates the demo database.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

DISK=/dev/disk/azure/scsi1/lun0
PART="${DISK}-part1"
LABEL=shareddata
MNT=/mnt/shared

[[ -b "$DISK" ]] || { echo "Shared disk not found at $DISK"; exit 1; }
if [[ -b "$PART" ]] && blkid "$PART" >/dev/null 2>&1; then
  echo "$PART already has a filesystem – refusing to format. Use activate.sh instead."
  exit 1
fi

echo ">> Partitioning and formatting $DISK"
parted -s "$DISK" mklabel gpt mkpart primary ext4 0% 100%
partprobe "$DISK"; udevadm settle; sleep 2
mkfs.ext4 -F -L "$LABEL" "$PART"

echo ">> Copying MySQL data + app onto the shared disk"
mkdir -p "$MNT"
mount "$PART" "$MNT"
systemctl stop mysql || true
mkdir -p "$MNT"/{mysql,app,config}
rsync -a /var/lib/mysql/ "$MNT/mysql/"
chown mysql:mysql "$MNT/mysql"
cp /etc/mysql/debian.cnf "$MNT/config/debian.cnf"   # same maintenance creds on both nodes
cp "$HERE/app/app.py" "$MNT/app/app.py"

DB_PASS="$(openssl rand -hex 16)"
cat > "$MNT/app/app.env" <<EOF
DB_USER=demo
DB_PASS=$DB_PASS
DB_NAME=demo
PORT=80
EOF
chmod 600 "$MNT/app/app.env"
chmod 644 "$MNT/app/app.py"
sync
umount "$MNT"

echo ">> Activating this node"
"$HERE/activate.sh"

echo ">> Creating database, user and table"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS demo;
CREATE USER IF NOT EXISTS 'demo'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON demo.* TO 'demo'@'localhost';
FLUSH PRIVILEGES;
CREATE TABLE IF NOT EXISTS demo.notes (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message    VARCHAR(500) NOT NULL,
  written_by VARCHAR(64)  NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO demo.notes (message, written_by) VALUES ('Shared disk initialised', '$(hostname)');
SQL

systemctl restart demo-app
echo "Done. Open http://<vm01-public-ip>/"
