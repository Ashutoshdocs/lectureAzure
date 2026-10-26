#!/usr/bin/env bash
# One-shot deploy of the Container Apps demo. Requires: Azure CLI (az) logged in.
# Usage:  ./deploy.sh            (uses defaults below; override with env vars)
set -euo pipefail

RG="${RG:-rg-aca-demo}"
LOCATION="${LOCATION:-centralindia}"
ENV_NAME="${ENV_NAME:-aca-demo-env}"
ACR="${ACR:-acrdemo$RANDOM$RANDOM}"   # must be globally unique, lowercase
FRONTEND=frontend
BACKEND=backend
JOB=batch-job

echo "==> Installing/updating the containerapp CLI extension"
az extension add --name containerapp --upgrade --only-show-errors
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

echo "==> Resource group + container registry"
az group create -n "$RG" -l "$LOCATION" -o none
az acr create -g "$RG" -n "$ACR" --sku Basic --admin-enabled true -o none

echo "==> Building images in the cloud (no local Docker needed)"
az acr build -r "$ACR" -t aca-demo:v1 ./app  -o none
az acr build -r "$ACR" -t aca-job:v1  ./job  -o none

ACR_SERVER="$ACR.azurecr.io"
ACR_USER=$(az acr credential show -n "$ACR" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR" --query "passwords[0].value" -o tsv)
REG_ARGS=(--registry-server "$ACR_SERVER" --registry-username "$ACR_USER" --registry-password "$ACR_PASS")

echo "==> Container Apps environment (shared network boundary + logs)"
az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOCATION" -o none

echo "==> Backend: INTERNAL ingress only (not reachable from the internet)"
az containerapp create -g "$RG" -n "$BACKEND" --environment "$ENV_NAME" \
  --image "$ACR_SERVER/aca-demo:v1" "${REG_ARGS[@]}" \
  --target-port 8080 --ingress internal \
  --min-replicas 0 --max-replicas 3 \
  --env-vars APP_ROLE=backend APP_MESSAGE="I am the internal backend" APP_COLOR="#7c3aed" \
  -o none

echo "==> Frontend: EXTERNAL ingress, scale 0..10 on HTTP concurrency"
az containerapp create -g "$RG" -n "$FRONTEND" --environment "$ENV_NAME" \
  --image "$ACR_SERVER/aca-demo:v1" "${REG_ARGS[@]}" \
  --target-port 8080 --ingress external \
  --revision-suffix v1 \
  --min-replicas 0 --max-replicas 10 \
  --scale-rule-name http-rule --scale-rule-type http --scale-rule-http-concurrency 5 \
  --env-vars APP_IMAGE="$ACR_SERVER/aca-demo:v1" APP_ROLE=frontend APP_VERSION=v1 APP_COLOR="#2563eb" BACKEND_URL="http://$BACKEND" \
  -o none

echo "==> Job: run-to-completion container, triggered manually"
az containerapp job create -g "$RG" -n "$JOB" --environment "$ENV_NAME" \
  --image "$ACR_SERVER/aca-job:v1" "${REG_ARGS[@]}" \
  --trigger-type Manual --replica-timeout 300 --replica-retry-limit 1 \
  --replica-completion-count 1 --parallelism 1 \
  --env-vars STEPS=5 \
  -o none

FQDN=$(az containerapp show -g "$RG" -n "$FRONTEND" --query properties.configuration.ingress.fqdn -o tsv)
cat <<EOF

Done!
  Demo UI:   https://$FQDN
  Registry:  $ACR_SERVER

Save these for the next steps in README.md:
  export RG=$RG ACR=$ACR ENV_NAME=$ENV_NAME
EOF
