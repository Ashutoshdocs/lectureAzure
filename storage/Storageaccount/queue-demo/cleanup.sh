#!/usr/bin/env bash
# Deletes everything the demo created (the whole resource group).
set -euo pipefail
RG="${RG:-rg-queue-demo}"
echo "Deleting resource group $RG (VM, disk, NIC, IP, storage account, queues)..."
az group delete -n "$RG" --yes --no-wait
echo "Deletion started. Check with: az group exists -n $RG"
