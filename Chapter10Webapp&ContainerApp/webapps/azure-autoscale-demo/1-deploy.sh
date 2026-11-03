#!/usr/bin/env bash
# Step 1: create the resource group, an S1 Linux plan and the web app, then push the code.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
echo "$APP" > "$STATE_FILE"

echo "==> Resource group $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

echo "==> App Service plan $PLAN ($SKU, Linux)"
az appservice plan create -g "$RG" -n "$PLAN" --sku "$SKU" --is-linux --number-of-workers 1 -o none

echo "==> Web app $APP (Node 20)"
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "NODE:20-lts" -o none

echo "==> Config: startup command, health check, and ARR affinity OFF"
# ARR affinity OFF is essential: otherwise a cookie pins your browser to ONE instance
# and you would never see the other pages after the scale-out.
az webapp config set -g "$RG" -n "$APP" --startup-file "node server.js" \
  --generic-configurations '{"healthCheckPath": "/healthz"}' -o none
az webapp update -g "$RG" -n "$APP" --client-affinity-enabled false -o none
az webapp config appsettings set -g "$RG" -n "$APP" \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none

echo "==> Zipping and pushing code"
rm -f app.zip
(cd app && zip -qr ../app.zip .)
az webapp deploy -g "$RG" -n "$APP" --src-path app.zip --type zip -o none

echo
echo "Deployed: $URL"
echo "Open it in a browser — you should see ONE instance name (e.g. 'Aurora')."
echo "Next: ./2-autoscale.sh"
