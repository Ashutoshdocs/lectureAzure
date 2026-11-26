#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"

echo "Current VMSS members:"
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{VM:name,InstanceId:instanceId,PowerState:powerState}" -o table

echo "Scaling VMSS capacity down to 1..."
echo "WARNING: Azure selects which eligible VMSS-managed instance(s) to remove."
az vmss scale -g "$RG" -n "$VMSS" --new-capacity 1

echo "Remaining VMSS members:"
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{VM:name,InstanceId:instanceId,PowerState:powerState}" -o table
