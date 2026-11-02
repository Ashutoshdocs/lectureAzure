#!/usr/bin/env bash
# Deploys the Node app to the App Service created by infra/01_deploy.sh.
# The client secret is NOT copied: the app reads it from Key Vault with its managed identity.
set -euo pipefail
cd "$(dirname "$0")"
source ../infra/.infra.env
source ./.env

az webapp config appsettings set -g "$RG" -n "$WEBAPP" -o none --settings \
  TENANT_ID="$TENANT_ID" CLIENT_ID="$CLIENT_ID" \
  WORKSPACE_ID="$WORKSPACE_ID" REPORT_ID="$REPORT_ID" DATASET_ID="$DATASET_ID" \
  RLS_ROLE_REGION="$RLS_ROLE_REGION" RLS_ROLE_ALL="$RLS_ROLE_ALL" \
  KEY_VAULT_NAME="$KEY_VAULT" NODE_ENV=production \
  SESSION_SECRET="$(openssl rand -hex 32)" SCM_DO_BUILD_DURING_DEPLOYMENT=true

az webapp config set -g "$RG" -n "$WEBAPP" --startup-file "npm start" -o none
az webapp update -g "$RG" -n "$WEBAPP" --https-only true -o none

rm -f ../app.zip
zip -qr ../app.zip . -x "node_modules/*" ".env" "deploy_webapp.sh"
az webapp deploy -g "$RG" -n "$WEBAPP" --src-path ../app.zip --type zip -o none
echo "Deployed: https://$WEBAPP.azurewebsites.net"
