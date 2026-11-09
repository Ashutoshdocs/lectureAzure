#!/usr/bin/env bash
set -euo pipefail

# Run from Bash (Azure Cloud Shell or Ubuntu). Edit variables in config.env first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

command -v az >/dev/null || { echo "Azure CLI is required."; exit 1; }
az account show >/dev/null

echo "Subscription:"
az account show --query '{name:name,id:id,tenantId:tenantId}' -o table

az group create -n "$RG" -l "$LOCATION" -o table

az network nsg create -g "$RG" -n "$NSG" -l "$LOCATION" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-HTTP \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 80 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-SSH \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$SSH_SOURCE" --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 22 -o none

az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" \
  --address-prefixes 10.40.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefixes 10.40.1.0/24 \
  --network-security-group "$NSG" -o none

# Storage account names must be globally unique, lowercase, and 3-24 characters.
az storage account create -g "$RG" -n "$STORAGE" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false -o none

mkdir -p "$ROOT_DIR/generated"

ACCOUNT_KEY="$(az storage account keys list -g "$RG" -n "$STORAGE" --query '[0].value' -o tsv)"
az storage container create --name "$CONTAINER" --account-name "$STORAGE" \
  --account-key "$ACCOUNT_KEY" --public-access off -o none
az storage blob upload --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" \
  --container-name "$CONTAINER" --name setup-nginx.sh \
  --file "$SCRIPT_DIR/setup-nginx.sh" --overwrite true -o none

# Short-lived, read-only SAS. It is passed to Custom Script Extension as protected settings.
EXPIRY="$(date -u -d '+1 day' '+%Y-%m-%dT%H:%MZ')"
SAS="$(az storage blob generate-sas --account-name "$STORAGE" --account-key "$ACCOUNT_KEY" \
  --container-name "$CONTAINER" --name setup-nginx.sh --permissions r \
  --expiry "$EXPIRY" --https-only -o tsv)"
BLOB_URL="https://${STORAGE}.blob.core.windows.net/${CONTAINER}/setup-nginx.sh"
export BLOB_WITH_SAS="${BLOB_URL}?${SAS}"
python3 - "$ROOT_DIR/generated/cse-protected-settings.json" <<'PY'
import json, os, sys
settings = {"fileUris": [os.environ["BLOB_WITH_SAS"]], "commandToExecute": "bash setup-nginx.sh"}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(settings, output)
PY

echo "Infrastructure and private Blob script created."
echo "Storage account: $STORAGE"
echo "Script blob: $BLOB_URL"
echo "A read-only SAS valid for approximately 24 hours was saved in generated/cse-protected-settings.json."
echo "Protect that file; it contains a temporary SAS credential."
