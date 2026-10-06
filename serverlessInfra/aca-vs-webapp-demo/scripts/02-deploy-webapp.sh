#!/usr/bin/env bash
# Step 2: App Service Plan + Web App running the v1 image from ACR
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"

ACR_USER=$(az acr credential show -n "$ACR_NAME" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR_NAME" --query "passwords[0].value" -o tsv)

echo ">> Creating Linux App Service Plan ($PLAN_SKU) - you pay for this VM 24x7"
az appservice plan create -n "$PLAN_NAME" -g "$RG" -l "$LOCATION" --is-linux --sku "$PLAN_SKU" -o none

echo ">> Creating Web App from the ACR image"
az webapp create -n "$WEBAPP_NAME" -g "$RG" -p "$PLAN_NAME" \
  --container-image-name "${ACR_SERVER}/${IMAGE_NAME}:v1" \
  --container-registry-url "https://${ACR_SERVER}" \
  --container-registry-user "$ACR_USER" \
  --container-registry-password "$ACR_PASS" -o none

echo ">> Telling App Service which port the container listens on"
az webapp config appsettings set -n "$WEBAPP_NAME" -g "$RG" \
  --settings WEBSITES_PORT=8000 -o none

echo ">> Always On = the instance never sleeps"
az webapp config set -n "$WEBAPP_NAME" -g "$RG" --always-on true -o none

WEBAPP_URL="https://$(az webapp show -n "$WEBAPP_NAME" -g "$RG" --query defaultHostName -o tsv)"
echo "WEBAPP_URL=$WEBAPP_URL" >> "$STATE_FILE"

echo ">> Waiting for the container to start (first pull can take 1-2 min)..."
for i in $(seq 1 30); do
  if curl -fs "$WEBAPP_URL/health" >/dev/null; then echo "   up!"; break; fi
  sleep 10
done
echo "Web App URL: $WEBAPP_URL"
