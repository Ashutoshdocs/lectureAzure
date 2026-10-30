#!/bin/bash
set -euo pipefail
: "${RG:?}" "${GALLERY:?}" "${IMAGE_DEF:?}"

# All versions as "name id", sorted by semantic version (same rule Azure uses)
mapfile -t VERSIONS < <(az sig image-version list \
  -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
  --query "[?publishingProfile.excludeFromLatest!=\`true\`].[name,id]" -o tsv | sort -V -k1,1)

if [ ${#VERSIONS[@]} -eq 0 ]; then echo "No versions found"; exit 1; fi

NEWEST_ID=$(echo "${VERSIONS[-1]}" | awk '{print $2}')
NEWEST_NAME=$(echo "${VERSIONS[-1]}" | awk '{print $1}')

for row in "${VERSIONS[@]}"; do
  id=$(echo "$row" | awk '{print $2}')
  if [ "$id" == "$NEWEST_ID" ]; then
    az tag update --resource-id "$id" --operation Merge --tags latest=true  -o none
  else
    az tag update --resource-id "$id" --operation Merge --tags latest=false -o none
  fi
done

echo "Latest image version is now: $NEWEST_NAME"
az sig image-version list -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
  --query "[].{version:name, latestTag:tags.latest, state:provisioningState}" -o table
