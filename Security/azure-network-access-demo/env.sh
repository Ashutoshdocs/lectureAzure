#!/usr/bin/env bash
# ------------------------------------------------------------------
# Shared settings + helper functions used by every demo script.
# You normally do NOT run this file directly; each script sources it.
# ------------------------------------------------------------------
set -euo pipefail

# ---- Change these if you like ------------------------------------
LOCATION="${LOCATION:-centralindia}"   # any Azure region close to you
RG="${RG:-rg-network-demo}"            # one resource group holds everything
VM_SIZE="${VM_SIZE:-Standard_B1s}"     # if unavailable in your region try Standard_B2ats_v2
# ------------------------------------------------------------------

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$DEMO_DIR/.demo-state"

# A random suffix so globally-unique names (storage, web app) don't clash.
if [[ ! -f "$STATE_FILE" ]]; then
  printf 'SUFFIX=%04x%02x\n' "$RANDOM" "$((RANDOM % 256))" > "$STATE_FILE"
fi
# shellcheck disable=SC1090
source "$STATE_FILE"

# Fixed names used across scripts
VNET_CONSUMER="vnet-consumer"      # "our" network: 10.1.0.0/16
VNET_PROVIDER="vnet-provider"      # someone else's network: 10.2.0.0/16
TEST_VM="vm-test"                  # the VM we test FROM (inside vnet-consumer)
SA_PUBLIC="stpub${SUFFIX}"         # storage for demo 1 (public endpoint, VNet-restricted)
SA_PRIVATE="stpriv${SUFFIX}"       # storage for demo 2 (private endpoint)
WEBAPP="app-vnetint-${SUFFIX}"     # web app for demo 5 (VNet integration)

# Save a key=value so later scripts can reuse it
save_state() {
  local key="$1" value="$2"
  grep -v "^${key}=" "$STATE_FILE" > "$STATE_FILE.tmp" || true
  echo "${key}=${value}" >> "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Run a shell snippet INSIDE the test VM (no SSH / public IP needed)
run_on_vm() {
  az vm run-command invoke -g "$RG" -n "$TEST_VM" \
    --command-id RunShellScript --scripts "$1" \
    --query 'value[0].message' -o tsv
}

# Pretty section headers
step() { echo; echo "================================================================"; echo "  $*"; echo "================================================================"; }
info() { echo "  -> $*"; }

# SAS expiry 1 day from now (works on GNU date / Azure Cloud Shell and macOS)
sas_expiry() { date -u -d '+1 day' '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -v+1d '+%Y-%m-%dT%H:%MZ'; }
