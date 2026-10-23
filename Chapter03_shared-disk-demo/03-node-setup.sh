#!/usr/bin/env bash
# STEP 4 – run on BOTH vm01 and vm02:  sudo ./03-node-setup.sh
# Installs MySQL + Python libs, disables MySQL autostart (the shared disk is
# mounted only by the active node), and installs the app's systemd unit.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mysql-server python3-flask python3-pymysql parted rsync

# Both nodes must run the SAME MySQL version against the same data files
apt-mark hold mysql-server mysql-server-8.0 mysql-client-8.0 >/dev/null 2>&1 || true

# MySQL must NOT start at boot – activate.sh starts it after mounting the disk
systemctl stop mysql
systemctl disable mysql

mkdir -p /mnt/shared

cat > /etc/systemd/system/demo-app.service <<'EOF'
[Unit]
Description=Shared-disk demo frontend (code lives on the shared disk)
After=network.target mysql.service
Requires=mysql.service
ConditionPathExists=/mnt/shared/app/app.py

[Service]
EnvironmentFile=/mnt/shared/app/app.env
ExecStart=/usr/bin/python3 /mnt/shared/app/app.py
User=www-data
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
# Not enabled on purpose – activate.sh starts it.

chmod +x "$(dirname "$0")"/*.sh
echo "Node setup done on $(hostname). Shared disk device:"
ls -l /dev/disk/azure/scsi1/ 2>/dev/null || echo "WARNING: no data disk at /dev/disk/azure/scsi1 – is the shared disk attached?"
