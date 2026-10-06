#!/usr/bin/env bash
# DEMO 1: Same image, two platforms. Show what each platform injects and how it is modelled.
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"

line(){ printf '\n\033[1;36m==== %s ====\033[0m\n' "$1"; }

line "Same image on both?"
echo "Web App image      : $(az webapp config show -n "$WEBAPP_NAME" -g "$RG" --query linuxFxVersion -o tsv)"
echo "Container App image: $(az containerapp show -n "$ACA_NAME" -g "$RG" --query "properties.template.containers[0].image" -o tsv)"

line "Web App response (/api/info)"
curl -s "$WEBAPP_URL/api/info" | python3 -m json.tool

line "Container App response (/api/info)"
curl -s "$ACA_URL/api/info" | python3 -m json.tool

line "Compute model: Web App = fixed VM instances in a plan"
az appservice plan show -n "$PLAN_NAME" -g "$RG" \
  --query "{sku:sku.name, tier:sku.tier, instances:sku.capacity, alwaysBilled:'yes, per instance per hour'}" -o table

line "Compute model: Container App = replicas per revision, governed by scale rules"
az containerapp show -n "$ACA_NAME" -g "$RG" \
  --query "{minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas, rule:properties.template.scale.rules[0].name, cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory}" -o table
echo "Current replicas: $(az containerapp replica list -n "$ACA_NAME" -g "$RG" --query 'length(@)' -o tsv)"
