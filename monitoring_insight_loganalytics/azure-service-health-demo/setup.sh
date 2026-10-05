#!/usr/bin/env bash
# Azure Service Health teaching demo — setup
# Usage:
#   ALERT_EMAIL="you@example.com" DEPLOY_VM=true ./setup.sh
set -euo pipefail

: "${ALERT_EMAIL:?Set ALERT_EMAIL, e.g. ALERT_EMAIL=you@example.com ./setup.sh}"
LOCATION="${LOCATION:-centralindia}"
RG_NAME="${RG_NAME:-rg-servicehealth-demo}"
REGIONS="${REGIONS:-Central India,South India,Global}"
DEPLOY_VM="${DEPLOY_VM:-false}"
VM_NAME="${VM_NAME:-vm-health-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking Azure CLI sign-in"
SUB_ID=$(az account show --query id -o tsv)
SUB_NAME=$(az account show --query name -o tsv)
echo "    Subscription: $SUB_NAME ($SUB_ID)"

echo "==> Registering resource providers (safe to re-run)"
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.ResourceHealth --wait

echo "==> Installing the Resource Graph CLI extension"
az extension add --name resource-graph --upgrade --only-show-errors

echo "==> Creating resource group $RG_NAME in $LOCATION"
az group create --name "$RG_NAME" --location "$LOCATION" --output none

# Convert "A,B,C" into a JSON array for the Bicep parameter
REGIONS_JSON=$(python3 -c 'import json,sys; print(json.dumps([r.strip() for r in sys.argv[1].split(",") if r.strip()]))' "$REGIONS")

echo "==> Deploying action group and alert rules (main.bicep)"
az deployment group create \
  --resource-group "$RG_NAME" \
  --name servicehealth-demo \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters alertEmail="$ALERT_EMAIL" regions="$REGIONS_JSON" \
  --output none

if [[ "$DEPLOY_VM" == "true" ]]; then
  echo "==> Deploying demo VM $VM_NAME (Standard_B1s) — used to trigger a Resource Health alert"
  az vm create \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address "" \
    --nsg "" \
    --output none
else
  echo "==> Skipping VM (set DEPLOY_VM=true to include it)"
fi

echo
echo "==> Deployed resources:"
az resource list --resource-group "$RG_NAME" --query "[].{name:name, type:type}" -o table

cat <<EOF

Setup complete.

Next steps:
  1. Check $ALERT_EMAIL — you should get an email saying you were added to action group 'ag-servicehealth-demo'.
  2. Wait ~5 minutes for the alert rules to become active before the live trigger.
  3. Follow DEMO-STEPS.md.
  4. Afterwards run ./cleanup.sh

Portal shortcuts:
  Service Health : https://portal.azure.com/#view/Microsoft_Azure_Health/AzureHealthBrowseBlade/~/serviceIssues
  Alert rules    : https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/alertsV2
EOF
