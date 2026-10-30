#!/bin/bash
set -euo pipefail
: "${RG:?}" "${GALLERY:?}" "${IMAGE_DEF:?}" "${LOCATION:?}"

VM_NAME="$1"
VERSION="$2"

echo ">> Deprovisioning $VM_NAME (removes machine-specific data and the build user)"
az vm run-command invoke -g "$RG" -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "sudo waagent -deprovision+user -force" -o none

echo ">> Deallocating and generalizing"
az vm deallocate -g "$RG" -n "$VM_NAME"
az vm generalize -g "$RG" -n "$VM_NAME"

VM_ID=$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv)

echo ">> Creating gallery image version $VERSION"
az sig image-version create \
  -g "$RG" --gallery-name "$GALLERY" \
  --gallery-image-definition "$IMAGE_DEF" \
  --gallery-image-version "$VERSION" \
  --virtual-machine "$VM_ID" \
  --target-regions "$LOCATION" \
  --replica-count 1 \
  --storage-account-type Standard_LRS \
  --tags latest=true imageVersion="$VERSION" sourceVm="$VM_NAME"

echo ">> Re-tagging: newest = latest=true, others = latest=false"
"$(dirname "$0")/tag-latest.sh"

echo ">> Deleting builder VM (a generalized VM can't be started again)"
az vm delete -g "$RG" -n "$VM_NAME" --yes --force-deletion none
