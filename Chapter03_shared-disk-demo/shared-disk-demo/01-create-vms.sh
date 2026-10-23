#!/usr/bin/env bash
# STEP 1 – run from your laptop / Cloud Shell (Azure CLI logged in: az login)
# Creates resource group, VNet, NSG (22 + 80) and two Ubuntu VMs in the same zone.
set -euo pipefail
source "$(dirname "$0")/config.env"

az group create -n "$RG" -l "$LOC" -o table

az network nsg create -g "$RG" -n "$NSG" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-ssh \
  --priority 1000 --access Allow --protocol Tcp --direction Inbound \
  --destination-port-ranges 22 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-http \
  --priority 1010 --access Allow --protocol Tcp --direction Inbound \
  --destination-port-ranges 80 -o none

az network vnet create -g "$RG" -n "$VNET" \
  --address-prefix 10.10.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefix 10.10.1.0/24 -o none
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
  --network-security-group "$NSG" -o none

for vm in "${VMS[@]}"; do
  echo ">> Creating $vm"
  az vm create -g "$RG" -n "$vm" \
    --image "$IMAGE" --size "$VM_SIZE" --zone "$ZONE" \
    --vnet-name "$VNET" --subnet "$SUBNET" --nsg "" \
    --public-ip-sku Standard \
    --admin-username "$ADMIN_USER" --generate-ssh-keys \
    -o table
done

echo
echo "Public IPs:"
az vm list-ip-addresses -g "$RG" \
  --query "[].{VM:virtualMachine.name, PublicIP:virtualMachine.network.publicIpAddresses[0].ipAddress}" -o table
