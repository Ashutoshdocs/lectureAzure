#!/usr/bin/env bash
# Appendix: Key Vault's NATIVE rotation policy (works for KEYS, not secrets).
# Your user also needs "Key Vault Crypto Officer" on the vault.
set -euo pipefail
source "$(dirname "$0")/../../scripts/00-env.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

az keyvault key create --vault-name "$KV" -n demo-key --kty RSA --size 2048 -o none
az keyvault key rotation-policy update --vault-name "$KV" -n demo-key --value "$HERE/policy.json" -o none
az keyvault key rotation-policy show --vault-name "$KV" -n demo-key

echo "Rotating now..."
az keyvault key rotate --vault-name "$KV" -n demo-key --query key.kid -o tsv
