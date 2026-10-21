SA="tsysysys"
CONTAINER="cccc"
BLOB_IP="172.16.1.4"

echo "===== 1. Check Private Endpoint connectivity ====="
nc -vz -w 5 "$BLOB_IP" 443

echo
echo "===== 2. Get a managed identity token ====="
TOKEN_JSON=$(curl --noproxy '*' -sS --connect-timeout 5 \
  -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F")

TOKEN=$(printf '%s' "$TOKEN_JSON" | python3 -c \
  'import json,sys; print(json.load(sys.stdin).get("access_token",""))')

if [ -z "$TOKEN" ]; then
  echo "FAILED: Could not obtain managed identity token."
  echo "$TOKEN_JSON"
  exit 1
fi
echo "SUCCESS: Managed identity token obtained."

echo
echo "===== 3. Request index.html from Blob Storage ====="
HTTP_CODE=$(curl --noproxy '*' -sS \
  --connect-timeout 5 --max-time 20 \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-ms-version: 2020-04-08" \
  -o /tmp/blob-response.txt \
  -w '%{http_code}' \
  "https://${SA}.blob.core.windows.net/${CONTAINER}/index.html")

echo "Blob HTTP status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  echo "SUCCESS: Blob retrieved through the Storage hostname."
else
  echo "Storage error response:"
  head -c 2000 /tmp/blob-response.txt
  echo
fi

unset TOKEN TOKEN_JSON