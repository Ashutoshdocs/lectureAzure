#!/usr/bin/env bash
# ------------------------------------------------------------------
# CLEANUP - delete EVERYTHING the demos created (one resource group).
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "Deleting resource group $RG (runs in the background, takes ~5-10 min)"
read -r -p "  Type the resource group name ($RG) to confirm: " answer
if [[ "$answer" != "$RG" ]]; then echo "  Cancelled."; exit 1; fi

az group delete -n "$RG" --yes --no-wait
rm -f "$STATE_FILE" "$STATE_FILE.tmp"
info "Deletion started. Check with: az group exists -n $RG"
