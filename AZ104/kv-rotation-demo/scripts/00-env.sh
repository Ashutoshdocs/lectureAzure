#!/usr/bin/env bash
# Shared settings. Sourced by every other script.
# Random names are generated ONCE and saved to .demo.env so every script
# (and every new terminal) uses the same resources.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.demo.env"

if [ ! -f "$ENV_FILE" ]; then
  N=$RANDOM
  cat > "$ENV_FILE" <<EOV
export RG=kv-demo-rg
export LOC=centralindia
export KV=kvdemo$N
export ST=kvdemost$N
export VM=kvdemo-vm
export FUNC=kvdemo-rotator-$N
export SECRET_NAME=app-api-key
export QUEUE=kv-events
export ROTATION_DAYS=90
EOV
  echo "Created $ENV_FILE (edit it to change names/region)"
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# Portable "N days from now" in UTC (GNU date on Linux, BSD date on macOS)
future_date() {
  date -u -d "+$1 days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+"$1"d '+%Y-%m-%dT%H:%M:%SZ'
}

# Lookups that only work once the resources exist (empty otherwise)
kv_id()  { az keyvault show -n "$KV" --query id -o tsv 2>/dev/null; }
st_id()  { az storage account show -n "$ST" -g "$RG" --query id -o tsv 2>/dev/null; }
vm_ip()  { az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv 2>/dev/null; }
