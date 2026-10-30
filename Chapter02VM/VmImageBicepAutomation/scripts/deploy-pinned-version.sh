#!/bin/bash
# Prove an OLDER image version still deploys (pinned, via CLI – Bicep always uses latest).
#
# Usage:   ./scripts/deploy-pinned-version.sh <version> [vm-name]
# Example: ./scripts/deploy-pinned-version.sh 1.0.0
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${GALLERY:?}" "${IMAGE_DEF:?}" "${VNET:?}" "${SUBNET:?}" "${ADMIN_USER:?}"

VERSION="${1:?version required, e.g. 1.0.0}"
VM="${2:-vm-pinned-${VERSION//./}}"

OLD_ID=$(az sig image-version show -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" -e "$VERSION" --query id -o tsv)

az vm create -g "$RG" -n "$VM" \
  --image "$OLD_ID" --size Standard_B2s --security-type TrustedLaunch \
  --vnet-name "$VNET" --subnet "$SUBNET" \
  --admin-username "$ADMIN_USER" --generate-ssh-keys \
  --public-ip-sku Standard --nsg-rule SSH -o none
az vm open-port -g "$RG" -n "$VM" --port 80 --priority 1010 -o none

IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
sleep 20
SERVED=$(curl -s --max-time 10 "http://$IP/version.txt" || true)
echo "$VM ($IP) serves: ${SERVED:-<no response>}"
[ "$SERVED" == "$VERSION" ] && echo "PASS ✅  pinned version $VERSION works" || { echo "FAIL ❌"; exit 1; }
