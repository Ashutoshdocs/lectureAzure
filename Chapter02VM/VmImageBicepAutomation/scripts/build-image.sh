#!/bin/bash
# Build one image version end to end:
#   create builder VM -> run change script -> check page -> capture -> retag latest
#
# Usage:
#   ./scripts/build-image.sh <version> <change-script> [base]
#     base = marketplace  -> start from Ubuntu 22.04 (use for the first image)
#     base = gallery      -> start from the current LATEST gallery image (default)
#
# Examples:
#   ./scripts/build-image.sh 1.0.0 scripts/v1-install-nginx.sh marketplace
#   ./scripts/build-image.sh 1.1.0 scripts/v2-change.sh
#   ./scripts/build-image.sh 1.2.0 scripts/v3-change.sh
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${GALLERY:?}" "${IMAGE_DEF:?}" "${VNET:?}" "${SUBNET:?}" "${ADMIN_USER:?}"

VERSION="${1:?version required, e.g. 1.0.0}"
CHANGE_SCRIPT="${2:?change script required}"
BASE="${3:-gallery}"
VM_NAME="vm-builder-${VERSION//./-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$BASE" == "marketplace" ]; then
  IMAGE="Ubuntu2204"
else
  # Image DEFINITION id (no version) = latest version
  IMAGE=$(az sig image-definition show -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" --query id -o tsv)
fi

echo ">> Creating builder VM $VM_NAME from: $IMAGE"
az vm create \
  -g "$RG" -n "$VM_NAME" \
  --image "$IMAGE" \
  --size Standard_B2s \
  --security-type TrustedLaunch \
  --vnet-name "$VNET" --subnet "$SUBNET" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg-rule SSH -o none

az vm open-port -g "$RG" -n "$VM_NAME" --port 80 --priority 1010 -o none

echo ">> Running $CHANGE_SCRIPT"
az vm run-command invoke -g "$RG" -n "$VM_NAME" \
  --command-id RunShellScript --scripts @"$CHANGE_SCRIPT" \
  --query "value[0].message" -o tsv

IP=$(az vm show -d -g "$RG" -n "$VM_NAME" --query publicIps -o tsv)
SERVED=$(curl -s --max-time 15 "http://$IP/version.txt" || true)
echo ">> Builder page serves version: ${SERVED:-<no response>}"
if [ "$SERVED" != "$VERSION" ]; then
  echo "WARNING: builder serves '$SERVED' but you are capturing '$VERSION'."
  read -r -p "Continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted. Builder VM $VM_NAME left running for inspection."; exit 1; }
fi

"$SCRIPT_DIR/capture.sh" "$VM_NAME" "$VERSION"
