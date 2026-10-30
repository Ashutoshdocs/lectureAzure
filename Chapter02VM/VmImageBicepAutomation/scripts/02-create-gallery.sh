#!/bin/bash
# Step 2 – Create the Compute Gallery and the image definition.
set -euo pipefail
: "${RG:?run: source ./scripts/env.sh}" "${LOCATION:?}" "${GALLERY:?}" "${IMAGE_DEF:?}"
: "${PUBLISHER:?}" "${OFFER:?}" "${SKU:?}"

az sig create -g "$RG" --gallery-name "$GALLERY" -l "$LOCATION" -o none

az sig image-definition create \
  -g "$RG" --gallery-name "$GALLERY" \
  --gallery-image-definition "$IMAGE_DEF" \
  --publisher "$PUBLISHER" --offer "$OFFER" --sku "$SKU" \
  --os-type Linux \
  --os-state Generalized \
  --hyper-v-generation V2 \
  --features SecurityType=TrustedLaunch -o none

echo "Created gallery $GALLERY with image definition $IMAGE_DEF"
