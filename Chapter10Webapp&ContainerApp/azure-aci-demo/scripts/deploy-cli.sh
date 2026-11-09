#!/usr/bin/env bash
# Optional: the same deployment as the README's portal steps, done with Azure CLI.
# Run from the project root in Azure Cloud Shell (Bash) or any shell with `az` logged in.
set -euo pipefail

RG="${RG:-rg-aci-demo}"
LOCATION="${LOCATION:-centralindia}"
ACR="${ACR:-acracidemo$RANDOM}"          # must be globally unique, lowercase, 5-50 chars
ACI="${ACI:-aci-hello-demo}"
DNS="${DNS:-aci-hello-$RANDOM}"          # must be unique within the region
IMAGE="aci-hello:v1"

az group create -n "$RG" -l "$LOCATION"
az acr create -g "$RG" -n "$ACR" --sku Basic --admin-enabled true
az acr build -r "$ACR" -t "$IMAGE" .

ACR_SERVER=$(az acr show -n "$ACR" --query loginServer -o tsv)
ACR_USER=$(az acr credential show -n "$ACR" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR" --query "passwords[0].value" -o tsv)

az container create -g "$RG" -n "$ACI" \
  --image "$ACR_SERVER/$IMAGE" \
  --registry-login-server "$ACR_SERVER" \
  --registry-username "$ACR_USER" \
  --registry-password "$ACR_PASS" \
  --os-type Linux --cpu 1 --memory 1.5 \
  --ports 80 --ip-address Public --dns-name-label "$DNS" \
  --restart-policy Always \
  --environment-variables APP_TITLE="Hello from ACI (CLI)" APP_ENV=demo APP_VERSION=1.0.0

FQDN=$(az container show -g "$RG" -n "$ACI" --query ipAddress.fqdn -o tsv)
echo ""
echo "Done! Open: http://$FQDN"
