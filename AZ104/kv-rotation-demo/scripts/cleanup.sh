#!/usr/bin/env bash
# Delete everything and purge the soft-deleted vault.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
read -rp "Delete resource group $RG and purge vault $KV? [y/N] " ok
[ "$ok" = "y" ] || exit 0
az group delete -n "$RG" --yes
az keyvault purge -n "$KV" || true
rm -f "$ENV_FILE"
echo "Cleaned up."
