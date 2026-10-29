#!/usr/bin/env bash
# STEP 7 – run from your laptop / Cloud Shell.
# Stops (deallocates) vm01, then makes vm02 the active node remotely.
#   ./05-failover-demo.sh            vm01 -> vm02
#   ./05-failover-demo.sh vm02 vm01  fail back
set -euo pipefail
source "$(dirname "$0")/config.env"

FROM="${1:-vm01}"
TO="${2:-vm02}"
REMOTE_DIR="/home/$ADMIN_USER/shared-disk-demo"

echo ">> Stopping (deallocating) $FROM ..."
az vm deallocate -g "$RG" -n "$FROM" -o none
az vm get-instance-view -g "$RG" -n "$FROM" \
  --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv

echo ">> Activating $TO (mount shared disk, start MySQL + app) ..."
az vm run-command invoke -g "$RG" -n "$TO" --command-id RunShellScript \
  --scripts "sudo $REMOTE_DIR/activate.sh --force" \
  --query "value[0].message" -o tsv

IP=$(az vm show -d -g "$RG" -n "$TO" --query publicIps -o tsv)
echo
echo "Open http://$IP/   (badge should now say $TO, old notes still there)"
