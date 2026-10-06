#!/usr/bin/env bash
# Shared variables. Every other script sources this file.
# A random suffix is generated ONCE and saved to .demo.env so names stay stable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$ROOT_DIR/.demo.env"

if [ ! -f "$STATE_FILE" ]; then
  echo "SUFFIX=$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)" > "$STATE_FILE"
fi
# shellcheck disable=SC1090
source "$STATE_FILE"

export LOCATION="${LOCATION:-centralindia}"
export RG="rg-aca-vs-webapp-${SUFFIX}"

# --- Azure Container Registry ---
export ACR_NAME="acrdemo${SUFFIX}"            # globally unique, alphanumeric only
export ACR_SERVER="${ACR_NAME}.azurecr.io"
export IMAGE_NAME="demoapp"

# --- Web App (App Service) ---
export PLAN_NAME="plan-demo-${SUFFIX}"
export PLAN_SKU="B1"                          # Basic: cheapest tier with Always On
export WEBAPP_NAME="webapp-demo-${SUFFIX}"

# --- Container App ---
export ACA_ENV_NAME="cae-demo-${SUFFIX}"
export ACA_NAME="aca-demo-${SUFFIX}"

echo "Resource group : $RG ($LOCATION)"
echo "ACR            : $ACR_SERVER"
echo "Web App        : $WEBAPP_NAME (plan $PLAN_NAME, $PLAN_SKU)"
echo "Container App  : $ACA_NAME (env $ACA_ENV_NAME)"
