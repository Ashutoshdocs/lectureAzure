#!/usr/bin/env bash
# Example command sequence for the lecture. Set RG and STG before running.
set -euo pipefail
: "${RG:?Set RG to your dedicated resource group}"
: "${STG:?Set STG to a globally unique Storage Account name}"
LOCATION="${LOCATION:-centralus}"

echo "1) Build"
az bicep build --file main.bicep

echo "2) Lint"
az bicep lint --file main.bicep || true

echo "3) Validate (no resources are created)"
az deployment group validate -g "$RG" -f main.bicep \
  -p storageAccountName="$STG" location="$LOCATION"

echo "4) What-if (preview only)"
az deployment group what-if -g "$RG" -f main.bicep \
  -p storageAccountName="$STG" location="$LOCATION"

echo "5) Deploy (this creates/updates resources)"
az deployment group create -g "$RG" -f main.bicep \
  -p storageAccountName="$STG" location="$LOCATION"

echo "6) What-if after deployment (expect no meaningful changes)"
az deployment group what-if -g "$RG" -f main.bicep \
  -p storageAccountName="$STG" location="$LOCATION"

echo "7) Deployment history"
az deployment group list -g "$RG" \
  --query "[].{name:name,state:properties.provisioningState}" -o table
