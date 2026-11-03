#!/usr/bin/env bash
# Step 2: attach CPU-based autoscale rules to the App Service plan.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

PLAN_ID=$(az appservice plan show -g "$RG" -n "$PLAN" --query id -o tsv)

echo "==> Autoscale setting $AUTOSCALE (min $MIN, max $MAX, start at 1)"
az monitor autoscale create -g "$RG" -n "$AUTOSCALE" --resource "$PLAN_ID" \
  --min-count "$MIN" --max-count "$MAX" --count 1 -o none

echo "==> Rule: scale OUT +1 when CpuPercentage > $SCALE_OUT_CPU% avg over $SCALE_OUT_WINDOW"
az monitor autoscale rule create -g "$RG" --autoscale-name "$AUTOSCALE" \
  --condition "CpuPercentage > $SCALE_OUT_CPU avg $SCALE_OUT_WINDOW" \
  --scale out 1 --cooldown "$COOLDOWN" -o none

echo "==> Rule: scale IN -1 when CpuPercentage < $SCALE_IN_CPU% avg over $SCALE_IN_WINDOW"
az monitor autoscale rule create -g "$RG" --autoscale-name "$AUTOSCALE" \
  --condition "CpuPercentage < $SCALE_IN_CPU avg $SCALE_IN_WINDOW" \
  --scale in 1 --cooldown "$COOLDOWN" -o none

az monitor autoscale rule list -g "$RG" --autoscale-name "$AUTOSCALE" -o table
echo
echo "Autoscale is live. Next: ./3-trigger-load.sh  (and ./4-watch.sh in a second terminal)"
