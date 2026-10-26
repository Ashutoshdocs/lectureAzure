#!/usr/bin/env bash
# Step 3: Container Apps Environment + Container App running the SAME v1 image
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"

ACR_USER=$(az acr credential show -n "$ACR_NAME" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR_NAME" --query "passwords[0].value" -o tsv)

echo ">> Creating Container Apps Environment"
echo "   (--logs-destination none: no Log Analytics workspace is created, keeping the demo to ACR + Web App + Container App only)"
az containerapp env create -n "$ACA_ENV_NAME" -g "$RG" -l "$LOCATION" \
  --logs-destination none -o none

echo ">> Creating Container App: scale 0..5 replicas, HTTP rule = 10 concurrent requests per replica"
az containerapp create -n "$ACA_NAME" -g "$RG" \
  --environment "$ACA_ENV_NAME" \
  --image "${ACR_SERVER}/${IMAGE_NAME}:v1" \
  --registry-server "$ACR_SERVER" \
  --registry-username "$ACR_USER" \
  --registry-password "$ACR_PASS" \
  --target-port 8000 --ingress external \
  --cpu 0.25 --memory 0.5Gi \
  --min-replicas 0 --max-replicas 5 \
  --scale-rule-name http-concurrency \
  --scale-rule-type http \
  --scale-rule-http-concurrency 10 \
  --revision-suffix v1 -o none

ACA_URL="https://$(az containerapp show -n "$ACA_NAME" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)"
echo "ACA_URL=$ACA_URL" >> "$STATE_FILE"

echo ">> Waiting for first response..."
for i in $(seq 1 30); do
  if curl -fs "$ACA_URL/health" >/dev/null; then echo "   up!"; break; fi
  sleep 5
done
echo "Container App URL: $ACA_URL"
