#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"
echo "This deletes the entire resource group $RG and all resources inside it."
read -r -p "Type DELETE-$RG to continue: " ANSWER
[[ "$ANSWER" == "DELETE-$RG" ]] || { echo "Cancelled."; exit 1; }
az group delete -n "$RG" --yes --no-wait
echo "Deletion started."
