#!/bin/bash
# Verification checklist: versions, tags, and which version each Bicep VM got.
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${GALLERY:?}" "${IMAGE_DEF:?}"

echo "== Image versions =="
az sig image-version list -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
  --query "[].{version:name, latest:tags.latest, excludeFromLatest:publishingProfile.excludeFromLatest, state:provisioningState}" -o table

echo
COUNT=$(az sig image-version list -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" --query "length([?tags.latest=='true'])" -o tsv)
echo "Versions tagged latest=true: $COUNT  (expected 1)"

echo
echo "== VMs and the exact image version they were built from =="
az vm list -g "$RG" \
  --query "[?storageProfile.imageReference.exactVersion!=null].{vm:name, imageVersion:storageProfile.imageReference.exactVersion}" -o table
