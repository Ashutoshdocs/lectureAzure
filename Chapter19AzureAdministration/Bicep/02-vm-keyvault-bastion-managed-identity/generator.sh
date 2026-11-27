#!/usr/bin/env bash
set -euo pipefail

# Generate credentials locally. Do not echo the password or put it in shell history.
read -r -p "Lab resource group (VM/network/Bastion): " LAB_RG
read -r -p "Existing Key Vault name: " VAULT_NAME
read -r -p "Key Vault resource group: " VAULT_RG
read -r -p "Secret name [bicep-vm-admin-password]: " SECRET_NAME
SECRET_NAME="${SECRET_NAME:-bicep-vm-admin-password}"
read -r -p "VM administrator username [vmadmin$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')]: " ADMIN_USER
ADMIN_USER="${ADMIN_USER:-vmadmin$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')}"

LOCATION="centralus"
VM_PASSWORD="$(openssl rand -base64 36 | tr -d '\n' | tr '/+' 'XY' | cut -c1-28)Aa1!"
PARAM_FILE="$(mktemp)"
chmod 600 "$PARAM_FILE"
cleanup() {
  unset VM_PASSWORD
  rm -f "$PARAM_FILE"
}
trap cleanup EXIT

az account show >/dev/null
az group show --name "$LAB_RG" >/dev/null
az keyvault show --name "$VAULT_NAME" --resource-group "$VAULT_RG" >/dev/null

echo "Saving generated password in the existing Key Vault..."
az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --value "$VM_PASSWORD" \
  --output none

# Secure parameters are written only to a mode-600 temporary file and removed on exit.
python3 - "$PARAM_FILE" "$ADMIN_USER" "$VM_PASSWORD" "$VAULT_NAME" "$SECRET_NAME" <<'PY'
import json, sys
path, username, password, vault, secret = sys.argv[1:]
data = {
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "adminUsername": {"value": username},
        "adminPassword": {"value": password},
        "keyVaultName": {"value": vault},
        "secretName": {"value": secret}
    }
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY

echo "Validating deployment..."
az deployment group validate \
  --resource-group "$LAB_RG" \
  --template-file main.bicep \
  --parameters @"$PARAM_FILE"

echo "Deploying VM, private network and Bastion in Central US..."
az deployment group create \
  --name "deploy-vm-keyvault-bastion" \
  --resource-group "$LAB_RG" \
  --template-file main.bicep \
  --parameters @"$PARAM_FILE" \
  --query properties.outputs \
  --output json

echo
echo "Deployment submitted. Generated username: $ADMIN_USER"
echo "Password secret: vault=$VAULT_NAME, secret=$SECRET_NAME"
echo "The password was not printed. Use the Key Vault to retrieve it for Bastion sign-in."
echo "IMPORTANT: ensure the VM system-assigned identity has Key Vault Secrets User permission."
