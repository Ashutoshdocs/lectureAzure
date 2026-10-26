#!/usr/bin/env bash
# Delete everything created by the demo (one resource group)
set -euo pipefail
source "$(dirname "$0")/00-variables.sh"
read -r -p "Delete resource group $RG and ALL its resources? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  az group delete -n "$RG" --yes --no-wait
  rm -f "$STATE_FILE"
  echo "Deletion started (runs in background, ~5 min)."
fi
