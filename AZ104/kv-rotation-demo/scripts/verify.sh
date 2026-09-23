#!/usr/bin/env bash
# Show all secret versions in Key Vault vs. what the app is using right now.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
echo "== Versions in Key Vault =="
az keyvault secret list-versions --vault-name "$KV" -n "$SECRET_NAME" \
  --query "sort_by([], &attributes.created)[].{version:id, created:attributes.created, expires:attributes.expires, enabled:attributes.enabled}" -o table
echo
echo "== Version the app is using =="
curl -s "http://$(vm_ip):8080/api/secret" | jq
