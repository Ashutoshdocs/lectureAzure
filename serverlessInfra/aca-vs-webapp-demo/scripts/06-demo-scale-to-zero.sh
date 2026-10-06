#!/usr/bin/env bash
# DEMO 3: Idle behaviour. Container App drops to 0 replicas (no compute charge);
# Web App keeps running (Always On) and keeps billing.
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"
line(){ printf '\n\033[1;36m==== %s ====\033[0m\n' "$1"; }

line "Waiting for Container App to scale to zero (needs ~5 min with no traffic)"
for i in $(seq 1 40); do
  n=$(az containerapp replica list -n "$ACA_NAME" -g "$RG" --query 'length(@)' -o tsv)
  echo "  $(date +%T)  ACA replicas: $n   |   Web App instances: $(az webapp list-instances -n "$WEBAPP_NAME" -g "$RG" --query 'length(@)' -o tsv)"
  [ "$n" = "0" ] && break
  sleep 30
done

line "First request after idle (cold start)"
echo "Container App:"
curl -s -o /tmp/aca.json -w "  total time: %{time_total}s\n" "$ACA_URL/api/info"
python3 -c "import json;d=json.load(open('/tmp/aca.json'));print('  instance:',d['instance'],'| uptime:',d['instance_uptime_seconds'],'s  <- brand-new replica')"

echo "Web App:"
curl -s -o /tmp/web.json -w "  total time: %{time_total}s\n" "$WEBAPP_URL/api/info"
python3 -c "import json;d=json.load(open('/tmp/web.json'));print('  instance:',d['instance'],'| uptime:',d['instance_uptime_seconds'],'s  <- same instance kept alive the whole time')"

echo
echo "Takeaway: ACA = pay nothing for compute while idle, small cold-start on first hit (set --min-replicas 1 to avoid it)."
echo "          Web App = always warm, always billed for the plan."
