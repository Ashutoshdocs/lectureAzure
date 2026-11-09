#!/usr/bin/env bash
# Deletes everything created by this demo (run in Azure Cloud Shell).
set -euo pipefail
RG="${RG:-rg-aci-demo}"
echo "Deleting resource group $RG ..."
az group delete --name "$RG" --yes --no-wait
echo "Deletion started. It will finish in a few minutes."
