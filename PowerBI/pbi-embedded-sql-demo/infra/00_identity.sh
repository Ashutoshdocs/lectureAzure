#!/usr/bin/env bash
# =====================================================================
# 00_identity.sh — Microsoft Entra ID objects for the demo
#   Groups:
#     sg-sql-admins        -> Microsoft Entra admin of the Azure SQL server
#     sg-pbi-sql-readers   -> humans who author reports in Power BI Desktop
#     sg-pbi-embed-sps     -> service principals allowed to call Power BI APIs (tenant setting)
#   App registrations (service principals):
#     app-pbi-embed        -> the web app's identity: calls Power BI REST API, generates embed tokens
#     app-sql-reader       -> credential stored in the gateway connection, reads Azure SQL
# Output: infra/.identity.env  (contains secrets — keep out of git)
# Requires: az login as a user who can create groups and app registrations.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

TENANT_ID=$(az account show --query tenantId -o tsv)
ME_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
ME_OID=$(az ad signed-in-user show --query id -o tsv)

ensure_group () {
  local name=$1
  local id
  id=$(az ad group list --display-name "$name" --query "[0].id" -o tsv)
  if [[ -z "$id" ]]; then
    id=$(az ad group create --display-name "$name" --mail-nickname "$name" --query id -o tsv)
  fi
  echo "$id"
}

ensure_app () {
  local name=$1
  local appid
  appid=$(az ad app list --display-name "$name" --query "[0].appId" -o tsv)
  if [[ -z "$appid" ]]; then
    appid=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  fi
  az ad sp show --id "$appid" >/dev/null 2>&1 || az ad sp create --id "$appid" >/dev/null
  echo "$appid"
}

add_member () {  # group-id member-object-id
  az ad group member check --group "$1" --member-id "$2" --query value -o tsv | grep -qi true \
    || az ad group member add --group "$1" --member-id "$2"
}

echo ">> Groups"
SQL_ADMINS_ID=$(ensure_group sg-sql-admins)
SQL_READERS_ID=$(ensure_group sg-pbi-sql-readers)
EMBED_SPS_ID=$(ensure_group sg-pbi-embed-sps)
add_member "$SQL_ADMINS_ID"  "$ME_OID"
add_member "$SQL_READERS_ID" "$ME_OID"

echo ">> App registration: app-pbi-embed (Power BI API caller)"
EMBED_APP_ID=$(ensure_app app-pbi-embed)
EMBED_SP_OID=$(az ad sp show --id "$EMBED_APP_ID" --query id -o tsv)
EMBED_SECRET=$(az ad app credential reset --id "$EMBED_APP_ID" --display-name demo --years 1 --query password -o tsv)
add_member "$EMBED_SPS_ID" "$EMBED_SP_OID"

echo ">> App registration: app-sql-reader (gateway -> SQL credential)"
SQLREADER_APP_ID=$(ensure_app app-sql-reader)
SQLREADER_SP_OID=$(az ad sp show --id "$SQLREADER_APP_ID" --query id -o tsv)
SQLREADER_SECRET=$(az ad app credential reset --id "$SQLREADER_APP_ID" --display-name demo --years 1 --query password -o tsv)

cat > .identity.env <<EOF
TENANT_ID=$TENANT_ID
ADMIN_UPN=$ME_UPN
ADMIN_OID=$ME_OID
SQL_ADMINS_GROUP=sg-sql-admins
SQL_ADMINS_GROUP_ID=$SQL_ADMINS_ID
EMBED_APP_ID=$EMBED_APP_ID
EMBED_SP_OID=$EMBED_SP_OID
EMBED_SECRET=$EMBED_SECRET
SQLREADER_APP_ID=$SQLREADER_APP_ID
SQLREADER_SP_OID=$SQLREADER_SP_OID
SQLREADER_SECRET=$SQLREADER_SECRET
EOF
chmod 600 .identity.env

echo
echo "Written infra/.identity.env (contains client secrets — do not commit)."
echo "IMPORTANT: do NOT grant admin-consent Power BI API permissions to app-pbi-embed;"
echo "service principals are authorised through the Power BI tenant setting + workspace role."
