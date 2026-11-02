#!/bin/bash

# ==============================
# VARIABLES
# ==============================
KEYVAULT_NAME="vaultxyz"
KEYVAULT_URL="https://${KEYVAULT_NAME}.vault.azure.net"
API_VERSION="7.4"

MYSQL_HOST="localhost"
DB_NAME="dbtest"
TABLE_NAME="tabletest"

START=21
END=40

# ==============================
# GET ACCESS TOKEN (IMDS)
# ==============================
ACCESS_TOKEN=$(curl -s \
  -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | jq -r '.access_token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "❌ Failed to get access token from IMDS"
  exit 1
fi

# ==============================
# FETCH MYSQL CREDS FROM VAULT
# ==============================
MYSQL_USER=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${KEYVAULT_URL}/secrets/userName?api-version=${API_VERSION}" \
  | jq -r '.value')

MYSQL_PASS=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${KEYVAULT_URL}/secrets/password?api-version=${API_VERSION}" \
  | jq -r '.value')

if [[ -z "$MYSQL_USER" || -z "$MYSQL_PASS" || "$MYSQL_USER" == "null" || "$MYSQL_PASS" == "null" ]]; then
  echo "❌ Failed to fetch MySQL credentials from Key Vault"
  exit 1
fi

echo "✅ MySQL credentials fetched securely"

# ==============================
# INSERT 20 MORE RECORDS
# ==============================
for i in $(seq $START $END)
do
mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" "$DB_NAME" <<EOF
INSERT INTO ${TABLE_NAME} (name, email)
VALUES ('User$i', 'user$i@example.com');
EOF
done

echo "✅ Inserted 20 more records (User${START} → User${END})"

