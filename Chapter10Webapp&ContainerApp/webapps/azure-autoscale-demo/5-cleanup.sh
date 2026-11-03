#!/usr/bin/env bash
# Step 5: delete everything so the S1 plan stops billing.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
echo "Deleting resource group $RG (app $APP, plan $PLAN, autoscale rules)..."
az group delete -n "$RG" --yes --no-wait
rm -f "$STATE_FILE" app.zip
echo "Delete started. It finishes in the background in a few minutes."
