#!/usr/bin/env bash
# =============================================================================
# bicep-deploy.sh - shared helper used by all Azure DevOps pipelines.
#
# Usage: ./scripts/bicep-deploy.sh <whatif|validate|create> <parameter-file>
#
# Reads subscriptionId + location from the environment parameter JSON,
# selects the subscription and runs the subscription-scope deployment of
# main/mainresource.bicep.
# =============================================================================
set -euo pipefail

MODE="${1:-}"
PARAM_FILE="${2:-}"
TEMPLATE_FILE="${TEMPLATE_FILE:-main/mainresource.bicep}"

[[ "$MODE" =~ ^(whatif|validate|create)$ ]] || { echo "Usage: $0 <whatif|validate|create> <parameter-file>"; exit 1; }
[[ -f "$PARAM_FILE" ]]    || { echo "##vso[task.logissue type=error]Parameter file not found: $PARAM_FILE"; exit 1; }
[[ -f "$TEMPLATE_FILE" ]] || { echo "##vso[task.logissue type=error]Template not found: $TEMPLATE_FILE"; exit 1; }

pf() { jq -r ".parameters.$1.value // empty" "$PARAM_FILE"; }
SUB_ID="$(pf subscriptionId)"
LOCATION="$(pf location)"
ENV_NAME="$(pf environment)"

# Fail fast if placeholders are still in the parameter file
if grep -q '"<[A-Z-]*>"' "$PARAM_FILE"; then
  echo "##vso[task.logissue type=error]Placeholders like <...> are still present in $PARAM_FILE:"
  grep -n '"<[A-Z-]*>"' "$PARAM_FILE" || true
  exit 1
fi
[[ "$SUB_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "##vso[task.logissue type=error]subscriptionId in $PARAM_FILE is not a valid GUID"; exit 1; }

echo "Environment : $ENV_NAME"
echo "Subscription: $SUB_ID"
echo "Location    : $LOCATION"
echo "Template    : $TEMPLATE_FILE"
echo "Parameters  : $PARAM_FILE"

az account set --subscription "$SUB_ID"
az bicep install >/dev/null 2>&1 || true
az bicep version

echo "---- bicep build (lint) ----"
az bicep build --file "$TEMPLATE_FILE" --stdout > /dev/null

DEPLOYMENT_NAME="mainresource-${ENV_NAME}-${BUILD_BUILDID:-local}"

case "$MODE" in
  whatif)
    echo "---- what-if ----"
    az deployment sub what-if \
      --name "$DEPLOYMENT_NAME" \
      --location "$LOCATION" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "@$PARAM_FILE" \
      --result-format FullResourcePayloads
    ;;
  validate)
    echo "---- validate ----"
    az deployment sub validate \
      --name "$DEPLOYMENT_NAME" \
      --location "$LOCATION" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "@$PARAM_FILE" \
      --output none
    echo "Validation succeeded."
    ;;
  create)
    echo "---- deploy ----"
    az deployment sub create \
      --name "$DEPLOYMENT_NAME" \
      --location "$LOCATION" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "@$PARAM_FILE" \
      --query properties.outputs -o json
    ;;
esac
