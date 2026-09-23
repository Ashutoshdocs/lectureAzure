#!/usr/bin/env bash
# DEMO option A (recommended): fire the REAL auto-rotation Function now,
# sending the same SecretNearExpiry event Key Vault would send.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

HOST=$(az functionapp show -g "$RG" -n "$FUNC" --query defaultHostName -o tsv)
EG_KEY=$(az functionapp keys list -g "$RG" -n "$FUNC" --query "systemKeys.eventgrid_extension" -o tsv)
ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)

curl -sS -o /dev/null -w "Function responded: HTTP %{http_code}\n" -X POST \
  "https://$HOST/runtime/webhooks/eventgrid?functionName=rotate_secret&code=$EG_KEY" \
  -H "Content-Type: application/json" \
  -H "aeg-event-type: Notification" \
  -d "[{
    \"id\": \"$ID\",
    \"eventType\": \"Microsoft.KeyVault.SecretNearExpiry\",
    \"subject\": \"$SECRET_NAME\",
    \"eventTime\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"dataVersion\": \"1\",
    \"data\": {\"VaultName\": \"$KV\", \"ObjectType\": \"Secret\", \"ObjectName\": \"$SECRET_NAME\"}
  }]"
echo "Watch the app: a new version should appear within ~5-15s (trigger: event-grid)."
