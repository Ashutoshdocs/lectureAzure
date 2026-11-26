#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"

echo "VMSS configuration:"
az vmss show -g "$RG" -n "$VMSS" \
  --query '{name:name,orchestrationMode:orchestrationMode,platformFaultDomainCount:platformFaultDomainCount,capacity:sku.capacity}' -o yaml

echo "VMSS members:"
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{name:name,instanceId:instanceId,provisioningState:provisioningState,powerState:powerState}" -o table

echo "Standalone VM association:"
az vm show -g "$RG" -n "$EXISTING_VM" \
  --query '{name:name,vmssId:virtualMachineScaleSet.id}' -o yaml

echo "Existing VM public IP:"
az vm list-ip-addresses -g "$RG" -n "$EXISTING_VM" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv
