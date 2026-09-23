#!/usr/bin/env bash
# Step 2: Ubuntu VM with a system-assigned managed identity (read-only on secrets).
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

az vm create -g "$RG" -n "$VM" \
  --image Ubuntu2204 --size Standard_B1s \
  --admin-username azureuser --generate-ssh-keys \
  --assign-identity --public-ip-sku Standard -o none

az vm open-port -g "$RG" -n "$VM" --port 8080 --priority 1010 -o none

VM_PRINCIPAL=$(az vm identity show -g "$RG" -n "$VM" --query principalId -o tsv)
az role assignment create --assignee-object-id "$VM_PRINCIPAL" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$(kv_id)" -o none

echo "VM public IP: $(vm_ip)"
