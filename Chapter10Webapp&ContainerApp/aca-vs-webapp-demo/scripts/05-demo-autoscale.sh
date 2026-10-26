#!/usr/bin/env bash
# DEMO 2: Send identical load to both. Container App adds replicas by itself;
# Web App stays on the instances you paid for in the plan.
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"

DURATION="${DURATION:-90}"
CONCURRENCY="${CONCURRENCY:-50}"
line(){ printf '\n\033[1;36m==== %s ====\033[0m\n' "$1"; }

line "BEFORE load"
echo "Web App instances      : $(az webapp list-instances -n "$WEBAPP_NAME" -g "$RG" --query 'length(@)' -o tsv)"
echo "Container App replicas : $(az containerapp replica list -n "$ACA_NAME" -g "$RG" --query 'length(@)' -o tsv)"

line "Load -> Web App  ($CONCURRENCY concurrent users, ${DURATION}s)"
python3 "$SCRIPT_DIR/load.py" "$WEBAPP_URL" "$DURATION" "$CONCURRENCY"

line "Load -> Container App  ($CONCURRENCY concurrent users, ${DURATION}s)"
python3 "$SCRIPT_DIR/load.py" "$ACA_URL" "$DURATION" "$CONCURRENCY" &
LOAD_PID=$!
for i in 1 2 3 4 5 6; do
  sleep 15
  echo "  [watch] Container App replicas now: $(az containerapp replica list -n "$ACA_NAME" -g "$RG" --query 'length(@)' -o tsv)"
done
wait $LOAD_PID

line "AFTER load"
echo "Web App instances      : $(az webapp list-instances -n "$WEBAPP_NAME" -g "$RG" --query 'length(@)' -o tsv)   (unchanged - no rule exists; scaling the plan is a manual/autoscale-settings job)"
echo "Container App replicas : $(az containerapp replica list -n "$ACA_NAME" -g "$RG" --query 'length(@)' -o tsv)   (scaled by the built-in HTTP rule: 10 concurrent req per replica)"
az containerapp replica list -n "$ACA_NAME" -g "$RG" --query "[].{replica:name, created:properties.createdTime}" -o table
