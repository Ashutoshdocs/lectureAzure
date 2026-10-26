#!/usr/bin/env bash
# Deletes everything the demo created.
set -euo pipefail
RG="${RG:-rg-aca-demo}"
az group delete -n "$RG" --yes --no-wait
echo "Deleting resource group $RG in the background."
