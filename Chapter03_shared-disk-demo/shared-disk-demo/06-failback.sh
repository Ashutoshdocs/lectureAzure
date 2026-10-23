#!/usr/bin/env bash
# STEP 8 – run from your laptop / Cloud Shell.
# Planned switch back: cleanly DEACTIVATE vm02, then ACTIVATE vm01.
#   ./06-failback.sh             vm02 -> vm01
#   ./06-failback.sh vm01 vm02   reverse direction (planned switch)
#
# Order matters: the old node releases the disk BEFORE the new node mounts it.
set -euo pipefail
source "$(dirname "$0")/config.env"

FROM="${1:-vm02}"    # currently active node – will be deactivated
TO="${2:-vm01}"      # node to make active
REMOTE_DIR="/home/$ADMIN_USER/shared-disk-demo"

power_state() {
  az vm get-instance-view -g "$RG" -n "$1" \
    --query "instanceView.statuses[?starts_with(code,'PowerState')].code | [0]" -o tsv
}

run_on() {   # run_on <vm> <command>  – prints the VM's stdout/stderr
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query "value[0].message" -o tsv
}

# 1. Make sure the target VM is running
if [[ "$(power_state "$TO")" != "PowerState/running" ]]; then
  echo ">> Starting $TO ..."
  az vm start -g "$RG" -n "$TO" -o none
fi
echo ">> $TO is running"

# 2. Cleanly release the disk on the currently active VM
FORCE=""
if [[ "$(power_state "$FROM")" == "PowerState/running" ]]; then
  echo ">> Deactivating $FROM (stop app + MySQL, unmount shared disk) ..."
  OUT="$(run_on "$FROM" "sudo $REMOTE_DIR/deactivate.sh")"
  echo "$OUT"
  if ! grep -q "is PASSIVE" <<<"$OUT"; then
    echo "!! Deactivate on $FROM did not complete – NOT activating $TO."
    echo "   Check: ssh $ADMIN_USER@<$FROM-ip> 'sudo $REMOTE_DIR/deactivate.sh'"
    exit 1
  fi
else
  # FROM is stopped/deallocated – it can't hold the disk, safe to take over
  echo ">> $FROM is not running – $TO will take over with --force"
  FORCE="--force"
fi

# 3. Activate the target VM
echo ">> Activating $TO ..."
OUT="$(run_on "$TO" "sudo $REMOTE_DIR/activate.sh $FORCE")"
echo "$OUT"
grep -q "is ACTIVE" <<<"$OUT" || { echo "!! Activation on $TO failed – see output above."; exit 1; }

IP=$(az vm show -d -g "$RG" -n "$TO" --query publicIps -o tsv)
echo
echo "Open http://$IP/   (badge should say $TO, notes from $FROM still there)"
