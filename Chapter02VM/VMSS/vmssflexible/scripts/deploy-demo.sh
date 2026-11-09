#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

CSE="$ROOT_DIR/generated/cse-protected-settings.json"
[[ -f "$CSE" ]] || { echo "Run scripts/create-infrastructure.sh first."; exit 1; }
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa.pub}"
[[ -f "$SSH_KEY" ]] || { echo "SSH public key not found: $SSH_KEY"; exit 1; }

echo "1/5 Creating standalone VM..."
az vm create -g "$RG" -n "$EXISTING_VM" -l "$LOCATION" \
  --image Ubuntu2204 --size "$VM_SIZE" --admin-username "$ADMIN_USER" \
  --ssh-key-values "$SSH_KEY" --vnet-name "$VNET" --subnet "$SUBNET" \
  --nsg "$NSG" --public-ip-sku Standard -o table

echo "2/5 Installing Nginx on the standalone VM from the Storage Account script..."
az vm extension set -g "$RG" --vm-name "$EXISTING_VM" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --settings '{}' --protected-settings "@$CSE" -o table

echo "3/5 Creating Flexible VMSS with one model-created VM..."
az vmss create -g "$RG" -n "$VMSS" -l "$LOCATION" \
  --orchestration-mode Flexible --platform-fault-domain-count 1 \
  --single-placement-group false --instance-count 1 \
  --image Ubuntu2204 --vm-sku "$VM_SIZE" \
  --admin-username "$ADMIN_USER" --ssh-key-values "$SSH_KEY" \
  --vnet-name "$VNET" --subnet "$SUBNET" --nsg "$NSG" \
  -o table

echo "4/5 Adding the Storage Account-backed Nginx setup to the VMSS model..."
az vmss extension set -g "$RG" --vmss-name "$VMSS" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --settings '{}' --protected-settings "@$CSE" -o table

echo "5/5 Attaching the existing standalone VM to the Flexible VMSS..."
VMSS_ID="$(az vmss show -g "$RG" -n "$VMSS" --query id -o tsv)"
az vm update -g "$RG" -n "$EXISTING_VM" \
  --set "virtualMachineScaleSet.id=$VMSS_ID" -o table

# Protect the attached VM from being selected for removal during the scale-in exercise.
EXISTING_INSTANCE_ID="$(az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[?name=='$EXISTING_VM'].instanceId | [0]" -o tsv)"
if [[ -n "$EXISTING_INSTANCE_ID" && "$EXISTING_INSTANCE_ID" != "None" ]]; then
  az vmss update -g "$RG" -n "$VMSS" --instance-id "$EXISTING_INSTANCE_ID" \
    --protect-from-scale-in -o none
  echo "Scale-in protection enabled for $EXISTING_VM (instance ID: $EXISTING_INSTANCE_ID)."
else
  echo "WARNING: Could not resolve the attached VM's VMSS instance ID; verify scale-in protection manually."
fi

echo
echo "Deployment complete. Existing VM remains a normal Azure VM resource and is now associated with VMSS."
echo "The VMSS model extension configures scale-out instances; the standalone VM was configured separately."
echo "Next: run scripts/scale-out.sh, then scripts/scale-in.sh."
