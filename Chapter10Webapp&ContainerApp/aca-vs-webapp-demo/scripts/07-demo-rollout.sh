#!/usr/bin/env bash
# DEMO 4: Releasing v2.
#  - Container App: v1 and v2 revisions live side-by-side, traffic split 80/20 (canary), instant rollback.
#  - Web App (B1, single slot): v2 replaces v1 in place via a container restart. All-or-nothing.
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"
line(){ printf '\n\033[1;36m==== %s ====\033[0m\n' "$1"; }

sample(){ # url, n -> count versions
  for _ in $(seq 1 "$2"); do curl -s "$1/api/info" | python3 -c "import sys,json;print(json.load(sys.stdin)['version'])"; done | sort | uniq -c
}

# ---------------- Container App ----------------
line "Container App: enable multiple-revision mode"
az containerapp revision set-mode -n "$ACA_NAME" -g "$RG" --mode multiple -o none

line "Container App: deploy v2 as a NEW revision (v1 keeps running)"
az containerapp update -n "$ACA_NAME" -g "$RG" \
  --image "${ACR_SERVER}/${IMAGE_NAME}:v2" --revision-suffix v2 -o none

line "Container App: split traffic 80% v1 / 20% v2 (canary)"
az containerapp ingress traffic set -n "$ACA_NAME" -g "$RG" \
  --revision-weight "${ACA_NAME}--v1=80" "${ACA_NAME}--v2=20" -o none
az containerapp revision list -n "$ACA_NAME" -g "$RG" \
  --query "[].{revision:name, active:properties.active, traffic:properties.trafficWeight, image:properties.template.containers[0].image}" -o table
sleep 10
echo "50 requests to the SAME URL:"
sample "$ACA_URL" 50

line "Container App: instant rollback to 100% v1 (no redeploy, no restart)"
az containerapp ingress traffic set -n "$ACA_NAME" -g "$RG" --revision-weight "${ACA_NAME}--v1=100" "${ACA_NAME}--v2=0" -o none
sleep 5; sample "$ACA_URL" 10

line "Container App: promote v2 to 100%"
az containerapp ingress traffic set -n "$ACA_NAME" -g "$RG" --revision-weight "${ACA_NAME}--v1=0" "${ACA_NAME}--v2=100" -o none
sleep 5; sample "$ACA_URL" 10

# ---------------- Web App ----------------
line "Web App: switch image to v2 (in-place replace + restart), probing every second"
ACR_USER=$(az acr credential show -n "$ACR_NAME" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR_NAME" --query "passwords[0].value" -o tsv)

( for _ in $(seq 1 120); do
    r=$(curl -s -m 3 "$WEBAPP_URL/api/info" | python3 -c "import sys,json;print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "DOWN/ERR")
    echo "$(date +%T) $r"; sleep 1
  done ) > /tmp/webapp_probe.log &
PROBE=$!

az webapp config container set -n "$WEBAPP_NAME" -g "$RG" \
  --container-image-name "${ACR_SERVER}/${IMAGE_NAME}:v2" \
  --container-registry-url "https://${ACR_SERVER}" \
  --container-registry-user "$ACR_USER" \
  --container-registry-password "$ACR_PASS" -o none
az webapp restart -n "$WEBAPP_NAME" -g "$RG"
wait $PROBE || true

echo "Probe timeline (version per second):"
uniq -c -f1 /tmp/webapp_probe.log | awk '{print "  " $3 " x" $1 " (from " $2 ")"}'
echo
echo "Takeaway: Web App on one slot can only be v1 OR v2. Canary/rollback needs deployment slots (Standard tier+)."
echo "          Container Apps gives revisions + weighted traffic out of the box on the consumption plan."
