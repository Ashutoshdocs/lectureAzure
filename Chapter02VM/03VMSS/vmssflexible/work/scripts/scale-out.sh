#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"

echo "Before scale-out:"
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{VM:name,PowerState:powerState,InstanceId:instanceId}" -o table

echo "Scaling VMSS capacity to 3..."
az vmss scale -g "$RG" -n "$VMSS" --new-capacity 3

echo "Waiting briefly for provisioning; extension installation can take several minutes."
sleep 20
echo "After scale-out:"
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{VM:name,InstanceId:instanceId,ProvisioningState:provisioningState}" -o table
echo "Check extension status and VM boot state; allow a few minutes for Nginx setup."
