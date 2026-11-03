#!/usr/bin/env bash
# Idempotent: creates the resource group, plan and web app only if they are missing,
# then (re)applies config and app settings. Safe to run on every pipeline run.
set -euo pipefail

while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2";; --app) APP="$2";; --rg) RG="$2";; --region) REGION="$2";;
    --sku) SKU="$2";; --runtime) RUNTIME="$2";; --build) BUILD="$2";; --commit) COMMIT="$2";;
    *) echo "Unknown arg $1"; exit 1;;
  esac
  shift 2
done
PLAN="plan-${APP}"

echo "Role=$ROLE App=$APP RG=$RG Region=$REGION Plan=$PLAN SKU=$SKU"

if [ "$(az group exists -n "$RG")" = "false" ]; then
  echo "Creating resource group $RG"
  az group create -n "$RG" -l "$REGION" -o none
else
  echo "Resource group $RG already exists"
fi

if ! az appservice plan show -g "$RG" -n "$PLAN" -o none 2>/dev/null; then
  echo "Creating App Service plan $PLAN ($SKU, Linux) in $REGION"
  az appservice plan create -g "$RG" -n "$PLAN" -l "$REGION" --sku "$SKU" --is-linux -o none
else
  echo "Plan $PLAN already exists"
fi

if ! az webapp show -g "$RG" -n "$APP" -o none 2>/dev/null; then
  echo "Creating web app $APP"
  az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "$RUNTIME" -o none
  echo "##vso[task.logissue type=warning]Created NEW web app $APP"
else
  echo "Web app $APP already exists — reusing it"
fi

az webapp config set -g "$RG" -n "$APP" --startup-file "node server.js" \
  --always-on true --generic-configurations '{"healthCheckPath": "/healthz"}' -o none
az webapp update -g "$RG" -n "$APP" --https-only true -o none
az webapp config appsettings set -g "$RG" -n "$APP" -o none --settings \
  SITE_ROLE="$ROLE" SITE_REGION="$REGION" BUILD_NUMBER="$BUILD" SOURCE_COMMIT="$COMMIT" \
  SCM_DO_BUILD_DURING_DEPLOYMENT=false

echo "Ready: https://${APP}.azurewebsites.net"
