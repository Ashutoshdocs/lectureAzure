#!/usr/bin/env bash
# Deploy dotnet10-webapp-demo to Azure App Service (Linux, .NET 10) from bash / Git Bash / Cloud Shell.
# Override any variable, e.g.:  APP=blazecheck RG=test ./deploy.sh
set -euo pipefail

RG="${RG:-rg-dotnet10-demo}"
LOCATION="${LOCATION:-centralindia}"
PLAN="${PLAN:-plan-dotnet10-demo}"
APP="${APP:-dotnet10-demo-$RANDOM}"
SKU="${SKU:-B1}"
RUNTIME="${RUNTIME:-DOTNETCORE:10.0}"
DLL="Dotnet10WebappDemo.dll"

cd "$(dirname "$0")"

echo "==> Building (dotnet publish)"
rm -rf publish app.zip
dotnet publish -c Release -o publish
(cd publish && zip -rq ../app.zip .)

if [ -z "$(az webapp list --query "[?name=='$APP'].name" -o tsv)" ]; then
  echo "==> Creating resource group, plan and web app ($RUNTIME)"
  az group create --name "$RG" --location "$LOCATION" --output none
  az appservice plan create --name "$PLAN" --resource-group "$RG" --sku "$SKU" --is-linux --output none
  az webapp create --name "$APP" --resource-group "$RG" --plan "$PLAN" --runtime "$RUNTIME" --output none
else
  echo "==> Using existing web app: $APP"
fi

echo "==> Setting runtime, startup command and health check"
az webapp config set --name "$APP" --resource-group "$RG" \
  --linux-fx-version "DOTNETCORE|10.0" \
  --startup-file "dotnet $DLL" \
  --generic-configurations '{"healthCheckPath": "/api/health"}' --output none
az webapp log config --name "$APP" --resource-group "$RG" \
  --docker-container-logging filesystem --output none

echo "==> Deploying app.zip"
az webapp deploy --name "$APP" --resource-group "$RG" --src-path app.zip --type zip

URL="https://$(az webapp show --name "$APP" --resource-group "$RG" --query defaultHostName -o tsv)"
echo ""
echo "Deployed: $URL"
echo "Health:   $URL/api/health"
echo "Logs:     az webapp log tail --name $APP --resource-group $RG"
echo "Cleanup:  az group delete --name $RG --yes --no-wait"
