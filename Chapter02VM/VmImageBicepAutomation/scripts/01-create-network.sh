#!/bin/bash
# Step 1 – Manual network setup (RG, VNet, Subnet). Bicep does NOT create these.
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${LOCATION:?}" "${VNET:?}" "${SUBNET:?}"

az group create -n "$RG" -l "$LOCATION" -o none

az network vnet create \
  -g "$RG" -n "$VNET" \
  --address-prefixes 10.50.0.0/16 \
  --subnet-name "$SUBNET" \
  --subnet-prefixes 10.50.1.0/24 -o none

echo "Created RG=$RG VNET=$VNET SUBNET=$SUBNET"
