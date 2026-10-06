#!/usr/bin/env bash
# Step 1: resource group + ACR, then build v1 and v2 images IN Azure (no local Docker needed)
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"

echo ">> Installing/upgrading the containerapp CLI extension"
az extension add --name containerapp --upgrade --only-show-errors

echo ">> Registering resource providers (one-time per subscription)"
for p in Microsoft.App Microsoft.Web Microsoft.ContainerRegistry; do
  az provider register --namespace "$p" --wait --only-show-errors
done

echo ">> Creating resource group"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> Creating Azure Container Registry (Basic, admin user enabled for simple pull auth)"
az acr create -n "$ACR_NAME" -g "$RG" -l "$LOCATION" --sku Basic --admin-enabled true -o none

echo ">> Building image v1 in ACR"
az acr build -r "$ACR_NAME" -t "${IMAGE_NAME}:v1" --build-arg APP_VERSION=v1 "$ROOT_DIR/app"

echo ">> Building image v2 in ACR (used later for the rollout demo)"
az acr build -r "$ACR_NAME" -t "${IMAGE_NAME}:v2" --build-arg APP_VERSION=v2 "$ROOT_DIR/app"

echo ">> Images in registry:"
az acr repository show-tags -n "$ACR_NAME" --repository "$IMAGE_NAME" -o table
