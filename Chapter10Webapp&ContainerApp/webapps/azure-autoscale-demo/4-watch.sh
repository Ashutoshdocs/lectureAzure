#!/usr/bin/env bash
# Step 4: watch the scale-out happen — instance count, CPU, distinct pages served.
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh
PLAN_ID=$(az appservice plan show -g "$RG" -n "$PLAN" --query id -o tsv)

while true; do
  clear
  echo "$(date '+%H:%M:%S')  $URL"
  echo
  WORKERS=$(az appservice plan show --ids "$PLAN_ID" --query "sku.capacity" -o tsv 2>/dev/null)
  echo "Plan instance count : ${WORKERS:-?}"
  echo "Running instances   :"
  az webapp list-instances -g "$RG" -n "$APP" --query "[].name" -o tsv 2>/dev/null | sed 's/^/   - /'

  CPU=$(az monitor metrics list --resource "$PLAN_ID" --metric CpuPercentage \
        --interval PT1M --offset 10m --aggregation Average \
        --query "value[0].timeseries[0].data[-3:].average" -o tsv 2>/dev/null | tr '\n' ' ')
  echo "Plan CPU % (last 3 min, avg): ${CPU:-n/a}"

  echo
  echo "Pages served by the site right now (12 requests):"
  for _ in $(seq 1 12); do
    curl -s --max-time 5 "$URL/api/whoami" | sed -n 's/.*"shortId":"\([^"]*\)","variant":"\([^"]*\)".*/\2 (\1)/p'
  done | sort | uniq -c | sed 's/^/  /'

  echo
  echo "Recent autoscale events:"
  az monitor activity-log list -g "$RG" --offset 1h \
    --query "[?contains(operationName.value, 'autoscale') || contains(operationName.value,'Autoscale')].{time:eventTimestamp, status:status.value, description:description}" \
    -o table 2>/dev/null | head -n 8
  sleep 30
done
