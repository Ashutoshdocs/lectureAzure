#!/usr/bin/env bash
# Reference command flow. Set RG and STG before running.
set -euo pipefail
: "${RG:?Set RG to the dedicated lab resource group}"
: "${STG:?Set STG to a globally unique Storage Account name}"

SUB_ID=$(az account show --query id -o tsv)
STACK_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Resources/deploymentStacks/stack-lifecycle"

az stack-whatif group create -n stack-lifecycle-preview -g "$RG" \
  --stack-id "$STACK_ID" -f main.bicep -p storageAccountName="$STG" \
  --action-on-unmanage detachAll --deny-settings-mode none --retention-interval P5D

az stack group create -n stack-lifecycle -g "$RG" \
  -f main.bicep -p storageAccountName="$STG" \
  --action-on-unmanage detachAll --deny-settings-mode none

az stack group show -n stack-lifecycle -g "$RG" -o json
az stack group list -g "$RG" -o table

# Update after removing one resource block:
az stack-whatif group create -n stack-lifecycle-preview-remove-images -g "$RG" \
  --stack-id "$STACK_ID" -f main-one-container.bicep -p storageAccountName="$STG" \
  --action-on-unmanage detachAll --deny-settings-mode none --retention-interval P5D

# Apply only after reviewing the preview:
az stack group create -n stack-lifecycle -g "$RG" \
  -f main-one-container.bicep -p storageAccountName="$STG" \
  --action-on-unmanage detachAll --deny-settings-mode none

# To delete resources removed from the template, preview and then explicitly
# change action-on-unmanage to deleteResources in this disposable lab.
