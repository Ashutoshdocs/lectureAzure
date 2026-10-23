#!/usr/bin/env bash
# STEP 2 – run from your laptop / Cloud Shell.
# Creates ONE Premium SSD with maxShares=2 and attaches it to BOTH VMs at LUN 0.
set -euo pipefail
source "$(dirname "$0")/config.env"

az disk create -g "$RG" -n "$DISK_NAME" \
  --size-gb "$DISK_SIZE_GB" --sku "$DISK_SKU" \
  --max-shares "$MAX_SHARES" --zone "$ZONE" -o table

for vm in "${VMS[@]}"; do
  echo ">> Attaching $DISK_NAME to $vm (LUN 0, caching None)"
  # Shared disks require host caching = None
  az vm disk attach -g "$RG" --vm-name "$vm" \
    --name "$DISK_NAME" --lun 0 --caching None -o none
done

echo
az disk show -g "$RG" -n "$DISK_NAME" \
  --query "{name:name, maxShares:maxShares, attachedTo:managedByExtended}" -o json
