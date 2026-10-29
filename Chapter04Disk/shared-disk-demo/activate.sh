#!/usr/bin/env bash
# Make THIS VM the active node: mount shared disk, start MySQL + app.
#   sudo ./activate.sh            normal
#   sudo ./activate.sh --force    take over after the other VM was stopped/crashed
#
# ext4 is NOT a cluster filesystem. Only ONE VM may mount the disk read-write.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

DISK=/dev/disk/azure/scsi1/lun0
DEV=/dev/disk/by-label/shareddata
MNT=/mnt/shared
ME="$(hostname)"
FORCE=0; [[ "${1:-}" == "--force" ]] && FORCE=1

# The partition may have been created while this VM was running – rescan
if [[ ! -e "$DEV" ]]; then
  partprobe "$DISK" || true; udevadm settle; sleep 2
fi
[[ -e "$DEV" ]] || { echo "Shared filesystem (label shareddata) not found. Run 04-init-shared-disk.sh on vm01 first."; exit 1; }

if ! mountpoint -q "$MNT"; then
  mkdir -p "$MNT"
  # Peek at the owner marker read-only, without replaying the journal
  mount -o ro,noload "$DEV" "$MNT"
  OWNER="$(cat "$MNT/ACTIVE_NODE" 2>/dev/null || true)"
  umount "$MNT"

  if [[ -n "$OWNER" && "$OWNER" != "$ME" && $FORCE -ne 1 ]]; then
    echo "Disk is marked ACTIVE on '$OWNER'."
    echo "Make sure $OWNER is stopped/deallocated (or run deactivate.sh there), then:"
    echo "  sudo ./activate.sh --force"
    exit 1
  fi
  mount -o rw "$DEV" "$MNT"     # ext4 journal replay happens here after a crash
fi

echo "$ME" > "$MNT/ACTIVE_NODE"; sync

# If MySQL is already running on the LOCAL datadir, "start" would be a no-op and
# it would keep serving the empty local database. Stop it before switching.
if ! mountpoint -q /var/lib/mysql; then
  if systemctl is-active --quiet mysql || pgrep -x mysqld >/dev/null; then
    echo ">> MySQL was running on the local disk – stopping it first"
    systemctl stop mysql demo-app || true
    sleep 2
  fi
  mount --bind "$MNT/mysql" /var/lib/mysql
fi
cp "$MNT/config/debian.cnf" /etc/mysql/debian.cnf
chmod 600 /etc/mysql/debian.cnf

systemctl restart mysql         # InnoDB crash recovery runs here if needed
systemctl restart demo-app

# Verify MySQL is really serving the shared-disk data
if ! mysql -Nse "SHOW DATABASES LIKE 'demo'" | grep -qx demo; then
  echo "!! MySQL is up but database 'demo' is missing – it is NOT using the shared data."
  echo "   Check: findmnt /var/lib/mysql ; sudo mysql -e 'select @@datadir'"
  echo "   Repair: sudo ./fix-db-user.sh"
fi

echo "== $ME is ACTIVE =="
systemctl --no-pager --lines=0 status mysql demo-app | grep -E "●|Active:"
