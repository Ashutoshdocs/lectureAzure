#!/usr/bin/env bash
# One-time setup, from zero:
#   1. create the Azure DevOps project
#   2. push this code into the project's Azure Repos git repo
#   3. create the Azure service connection (service principal)
#   4. create BOTH pipelines inside one pipeline folder
#
# Prereqs: az CLI logged in (az login) with rights to create a service principal,
#          az devops extension, git. Run from the repo root:  ./setup/setup-devops.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# ---------- EDIT THESE ----------
ORG_URL="https://dev.azure.com/YOUR-ORG"     # your Azure DevOps organization
PROJECT="WebApp-DR-Demo"
REPO="webapp-dr-demo"
PIPELINE_FOLDER='\WebApp-DR'                  # the folder both pipelines live in
SERVICE_CONNECTION="sc-azure-webapp-demo"     # must match pipelines/variables.yml
SP_NAME="sp-webapp-dr-demo"
# --------------------------------

grep -q "drdemo-CHANGEME" pipelines/variables.yml && {
  echo "Edit appBaseName in pipelines/variables.yml first (must be globally unique)."; exit 1; }

az extension add --name azure-devops --upgrade -y -o none
az devops configure --defaults organization="$ORG_URL"

echo "==> 1. Project $PROJECT"
if ! az devops project show -p "$PROJECT" -o none 2>/dev/null; then
  az devops project create --name "$PROJECT" --source-control git --visibility private -o none
fi
az devops configure --defaults organization="$ORG_URL" project="$PROJECT"

echo "==> 2. Repo $REPO + push code"
if ! az repos show -r "$REPO" -o none 2>/dev/null; then
  az repos create --name "$REPO" -o none
fi
REPO_URL=$(az repos show -r "$REPO" --query remoteUrl -o tsv)
[ -d .git ] || { git init -q -b main; }
git add -A
git -c user.name="setup" -c user.email="setup@example.com" commit -qm "Initial commit: app + primary/DR pipelines" || true
git branch -M main
git remote remove azure 2>/dev/null || true
git remote add azure "$REPO_URL"
# Uses your git credentials; for a PAT run: git push https://<anything>:<PAT>@dev.azure.com/...
git push -u azure main

echo "==> 3. Service connection $SERVICE_CONNECTION"
SUB_ID=$(az account show --query id -o tsv)
SUB_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
if ! az devops service-endpoint list --query "[?name=='$SERVICE_CONNECTION'].id" -o tsv | grep -q .; then
  SP_JSON=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor \
            --scopes "/subscriptions/$SUB_ID" -o json)
  export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY=$(echo "$SP_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')
  SP_APPID=$(echo "$SP_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["appId"])')
  az devops service-endpoint azurerm create --name "$SERVICE_CONNECTION" \
    --azure-rm-service-principal-id "$SP_APPID" --azure-rm-tenant-id "$TENANT_ID" \
    --azure-rm-subscription-id "$SUB_ID" --azure-rm-subscription-name "$SUB_NAME" -o none
  unset AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY
fi
SC_ID=$(az devops service-endpoint list --query "[?name=='$SERVICE_CONNECTION'].id" -o tsv)
az devops service-endpoint update --id "$SC_ID" --enable-for-all true -o none   # let pipelines use it

echo "==> 4. Pipelines in folder $PIPELINE_FOLDER"
create_pipeline () {
  local name="$1" yml="$2"
  if ! az pipelines show --name "$name" --folder-path "$PIPELINE_FOLDER" -o none 2>/dev/null; then
    az pipelines create --name "$name" --folder-path "$PIPELINE_FOLDER" \
      --repository "$REPO" --repository-type tfsgit --branch main \
      --yml-path "$yml" --skip-first-run true -o none
  fi
}
create_pipeline "01-Primary-Deploy" "pipelines/primary-deploy.yml"
create_pipeline "02-DR-Deploy"      "pipelines/dr-deploy.yml"

echo
echo "Done. Open: $ORG_URL/$PROJECT/_build?view=folders"
echo "Run the primary now:   az pipelines run --name 01-Primary-Deploy --folder-path '$PIPELINE_FOLDER'"
echo "Activate DR any time:  az pipelines run --name 02-DR-Deploy --folder-path '$PIPELINE_FOLDER' --parameters drRegion=southindia"
