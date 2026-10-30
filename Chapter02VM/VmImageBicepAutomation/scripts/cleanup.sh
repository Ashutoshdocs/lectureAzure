#!/bin/bash
# Cleanup.
#   ./scripts/cleanup.sh vms   -> delete demo VMs only (keeps gallery + network)
#   ./scripts/cleanup.sh all   -> delete the whole resource group
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}"

MODE="${1:-vms}"

if [ "$MODE" == "all" ]; then
  read -r -p "Delete resource group $RG and EVERYTHING in it? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] && az group delete -n "$RG" --yes --no-wait && echo "Deletion started."
  exit 0
fi

for v in $(az vm list -g "$RG" --query "[?starts_with(name,'vm-web-') || starts_with(name,'vm-pinned-')].name" -o tsv); do
  echo "Deleting $v"
  az vm delete -g "$RG" -n "$v" --yes
  # Bicep NSG / public IP are separate resources
  az network nsg delete -g "$RG" -n "$v-nsg" 2>/dev/null || true
  az network public-ip delete -g "$RG" -n "$v-pip" 2>/dev/null || true
done
echo "Done."
