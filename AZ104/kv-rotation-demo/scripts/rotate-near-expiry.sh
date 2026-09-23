#!/usr/bin/env bash
# DEMO option C: let Azure trigger rotation on its own by moving the expiry
# inside the 30-day near-expiry window. Key Vault emits SecretNearExpiry
# itself; this can take several minutes, so it's slower than options A/B.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
az keyvault secret set-attributes --vault-name "$KV" -n "$SECRET_NAME" \
  --expires "$(future_date 2)" --query "attributes.expires" -o tsv
echo "Expiry moved to 2 days from now. Wait for Key Vault to fire SecretNearExpiry."
