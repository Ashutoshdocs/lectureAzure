#!/usr/bin/env bash
# Azure Service Health teaching demo — cleanup
# Deletes the demo resource group, which removes the action group, both alert rules and the VM.
set -euo pipefail

RG_NAME="${RG_NAME:-rg-servicehealth-demo}"

if ! az group exists --name "$RG_NAME" | grep -q true; then
  echo "Resource group $RG_NAME does not exist. Nothing to clean up."
  exit 0
fi

echo "This will permanently delete resource group: $RG_NAME"
az resource list --resource-group "$RG_NAME" --query "[].{name:name, type:type}" -o table
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Cancelled."; exit 1; }

az group delete --name "$RG_NAME" --yes --no-wait
echo "Deletion started (runs in the background, ~5 minutes)."
echo "Check with: az group exists --name $RG_NAME"
