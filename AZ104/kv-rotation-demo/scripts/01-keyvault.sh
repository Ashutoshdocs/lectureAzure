#!/usr/bin/env bash
# Step 1: resource group, Key Vault (RBAC), and the secret with an expiry.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

az provider register -n Microsoft.EventGrid --wait
az group create -n "$RG" -l "$LOC" -o none

az keyvault create -n "$KV" -g "$RG" -l "$LOC" --enable-rbac-authorization true -o none
KV_ID=$(kv_id)

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee "$ME" --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none
echo "Waiting 60s for the role assignment to take effect..."
sleep 60

az keyvault secret set --vault-name "$KV" -n "$SECRET_NAME" \
  --value "$(openssl rand -base64 24)" \
  --expires "$(future_date "$ROTATION_DAYS")" \
  --tags rotationDays="$ROTATION_DAYS" \
  --query "{name:name, version:id, expires:attributes.expires}" -o table
