#!/bin/bash

# ==============================
# VARIABLES
# ==============================
KEYVAULT_NAME="vaultxyz"
KEYVAULT_URL="https://${KEYVAULT_NAME}.vault.azure.net"
API_VERSION="7.4"

DB_NAME="dbtest"
TABLE_NAME="tabletest"
MYSQL_HOST="localhost"

# ==============================
# GET ACCESS TOKEN FROM IMDS
# ==============================
echo "Fetching access token from Azure IMDS..."

ACCESS_TOKEN=$(curl -s \
  -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    echo "❌ Failed to obtain access token"
    exit 1
fi

echo "✅ Access token retrieved"

# ==============================
# FETCH MYSQL USERNAME
# ==============================
MYSQL_USER=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${KEYVAULT_URL}/secrets/userName?api-version=${API_VERSION}" \
  | jq -r '.value')

# ==============================
# FETCH MYSQL PASSWORD
# ==============================
MYSQL_PASS=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${KEYVAULT_URL}/secrets/password?api-version=${API_VERSION}" \
  | jq -r '.value')

# ==============================
# VALIDATE SECRETS
# ==============================
if [[ -z "$MYSQL_USER" || -z "$MYSQL_PASS" || "$MYSQL_USER" == "null" || "$MYSQL_PASS" == "null" ]]; then
    echo "❌ Failed to retrieve secrets from Key Vault"
    exit 1
fi

echo "✅ MySQL credentials fetched securely"

# ==============================
# FETCH DATA FROM MYSQL
# ==============================
echo "Fetching data from ${DB_NAME}.${TABLE_NAME}..."

mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" <<EOF
USE ${DB_NAME};
SELECT * FROM ${TABLE_NAME};
EOF

echo "✅ Data fetch completed successfully"

