#!/usr/bin/env bash
# Delete the Azure resources created by the pipelines (primary + all DR web apps).
# Optionally delete the Azure DevOps project too: ./setup/cleanup.sh --project
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=$(sed -n "s/^ *appBaseName: *'\([^']*\)'.*/\1/p" pipelines/variables.yml)
for RG in "rg-$BASE-primary" "rg-$BASE-dr"; do
  if [ "$(az group exists -n "$RG")" = "true" ]; then
    echo "Deleting $RG"; az group delete -n "$RG" --yes --no-wait
  fi
done
if [ "${1:-}" = "--project" ]; then
  PID=$(az devops project show -p WebApp-DR-Demo --query id -o tsv)
  az devops project delete --id "$PID" --yes
  az ad sp list --display-name sp-webapp-dr-demo --query "[].appId" -o tsv | xargs -r -n1 az ad sp delete --id
fi
echo "Cleanup started."
