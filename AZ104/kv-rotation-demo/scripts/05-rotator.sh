#!/usr/bin/env bash
# Step 5: Azure Function rotator + the "rotation policy" (SecretNearExpiry -> Function).
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

az functionapp create -g "$RG" -n "$FUNC" --storage-account "$ST" \
  --flexconsumption-location "$LOC" --runtime python --runtime-version 3.11 -o none

az functionapp identity assign -g "$RG" -n "$FUNC" -o none
FUNC_PRINCIPAL=$(az functionapp identity show -g "$RG" -n "$FUNC" --query principalId -o tsv)
az role assignment create --assignee-object-id "$FUNC_PRINCIPAL" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets Officer" --scope "$(kv_id)" -o none

( cd "$ROOT/rotator" && func azure functionapp publish "$FUNC" --python )

FUNC_ID=$(az functionapp show -g "$RG" -n "$FUNC" --query id -o tsv)
az eventgrid system-topic event-subscription create -g "$RG" \
  --system-topic-name kv-topic -n secret-near-expiry-rotate \
  --endpoint-type azurefunction \
  --endpoint "$FUNC_ID/functions/rotate_secret" \
  --included-event-types Microsoft.KeyVault.SecretNearExpiry \
  --subject-begins-with "$SECRET_NAME" -o none

echo "Auto-rotation wired: SecretNearExpiry -> $FUNC/rotate_secret"
