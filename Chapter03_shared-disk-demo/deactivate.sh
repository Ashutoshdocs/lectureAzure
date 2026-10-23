#!/usr/bin/env bash
# Cleanly release the shared disk from THIS VM:  sudo ./deactivate.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
MNT=/mnt/shared

systemctl stop demo-app || true
systemctl stop mysql    || true
mountpoint -q /var/lib/mysql && umount /var/lib/mysql
if mountpoint -q "$MNT"; then
  rm -f "$MNT/ACTIVE_NODE"
  sync
  umount "$MNT"
fi
echo "== $(hostname) is PASSIVE (shared disk released) =="
