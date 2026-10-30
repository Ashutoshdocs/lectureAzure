#!/bin/bash
# Deploy a VM with Bicep from the LATEST gallery image and prove it end to end.
#
# Usage:  ./scripts/deploy-bicep.sh <vm-name>
# Example: ./scripts/deploy-bicep.sh vm-web-v1
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${LOCATION:?}" "${GALLERY:?}" "${IMAGE_DEF:?}"
: "${SSH_PUBLIC_KEY:?export SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\"}"

VM="${1:?vm name required, e.g. vm-web-v1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_NAME="deploy-$VM"

echo ">> Deploying $VM with Bicep (image version is NOT specified: Azure picks latest)"
az deployment sub create \
  -n "$DEPLOY_NAME" -l "$LOCATION" \
  -f "$ROOT/bicep/main.bicep" \
  -p "$ROOT/bicep/main.bicepparam" \
  -p vmName="$VM" -o none

IP=$(az deployment sub show -n "$DEPLOY_NAME" --query properties.outputs.publicIp.value -o tsv)
USED=$(az deployment sub show -n "$DEPLOY_NAME" --query properties.outputs.imageVersionUsed.value -o tsv)
TAGGED=$(az sig image-version list -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
          --query "[?tags.latest=='true'].name | [0]" -o tsv)

# Give nginx a moment after first boot
SERVED=""
for i in $(seq 1 12); do
  SERVED=$(curl -s --max-time 5 "http://$IP/version.txt" || true)
  [ -n "$SERVED" ] && break
  sleep 10
done

echo
echo "VM name       : $VM"
echo "Public IP     : $IP"
echo "Bicep used    : $USED"
echo "Tagged latest : $TAGGED"
echo "Page serves   : ${SERVED:-<no response>}"
echo "Hostname check: $(curl -s --max-time 5 "http://$IP/" | grep -o 'Served by: [^<]*' || true)"
echo
if [ "$USED" == "$TAGGED" ] && [ "$USED" == "$SERVED" ]; then
  echo "PASS ✅  Bicep deployed the latest image ($USED)"
else
  echo "FAIL ❌  versions do not match"
  exit 1
fi
