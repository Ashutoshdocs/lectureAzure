#!/usr/bin/env bash
# DEMO option B: rotate manually by writing a new secret version.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
az keyvault secret set --vault-name "$KV" -n "$SECRET_NAME" \
  --value "$(openssl rand -base64 24)" \
  --expires "$(future_date "$ROTATION_DAYS")" \
  --tags rotationDays="$ROTATION_DAYS" \
  --query "{name:name, newVersion:id}" -o table
