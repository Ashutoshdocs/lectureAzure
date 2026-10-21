#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Azure Private Endpoint Teaching Lab — one-shot VM setup
# Ubuntu VM + nginx + Azure Blob Storage (via Private Endpoint)
#
# Usage (interactive):
#   sudo bash setup-private-storage-web.sh
# Usage (non-interactive):
#   sudo STORAGE_ACCOUNT=stpedemo123 CONTAINER_NAME=web \
#        PRIVATE_IP=10.0.2.4 WEB_PORT=80 bash setup-private-storage-web.sh
#
# Requirements:
#   - VM has a system-assigned managed identity
#   - Identity has "Storage Blob Data Reader" on the storage account
#   - NSG allows inbound TCP on WEB_PORT
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash $0"
    exit 1
fi

echo "=================================================="
echo " Azure VM -> Storage Private Endpoint Demo"
echo "=================================================="

# ---------- Inputs (env vars or prompts) ----------
[[ -z "${STORAGE_ACCOUNT:-}" ]] && read -rp "Storage Account name: " STORAGE_ACCOUNT
[[ -z "${CONTAINER_NAME:-}"  ]] && read -rp "Blob container name [web]: " CONTAINER_NAME
[[ -z "${PRIVATE_IP:-}"      ]] && read -rp "Storage Private Endpoint IP: " PRIVATE_IP
[[ -z "${WEB_PORT:-}"        ]] && read -rp "Web port for nginx [80]: " WEB_PORT

CONTAINER_NAME="${CONTAINER_NAME:-web}"
WEB_PORT="${WEB_PORT:-80}"

# ---------- Validation ----------
if [[ ! "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
    echo "ERROR: Storage account name must be 3-24 lowercase letters/digits."
    exit 1
fi

if [[ ! "$CONTAINER_NAME" =~ ^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$ ]]; then
    echo "ERROR: Invalid container name."
    exit 1
fi

if [[ ! "$WEB_PORT" =~ ^[0-9]+$ ]] || (( WEB_PORT < 1 || WEB_PORT > 65535 )); then
    echo "ERROR: Invalid port: $WEB_PORT"
    exit 1
fi

python3 - "$PRIVATE_IP" <<'PY'
import ipaddress, sys
try:
    ip = ipaddress.ip_address(sys.argv[1])
    if not ip.is_private or ip.is_loopback or ip.is_link_local:
        raise ValueError("not a valid private endpoint address")
except ValueError as exc:
    print(f"ERROR: {exc}")
    sys.exit(1)
PY

BLOB_HOST="${STORAGE_ACCOUNT}.blob.core.windows.net"
WEB_ROOT="/var/www/private-storage-demo"
HOSTS_TAG="# AZURE_PRIVATE_STORAGE_DEMO"
SYNC_SCRIPT="/usr/local/bin/sync-index.sh"

# ---------- 1. Packages ----------
echo
echo "[1/7] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx curl ca-certificates python3 gnupg

if ! command -v az >/dev/null 2>&1; then
    echo "Installing Azure CLI..."
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
    chmod a+r /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
      > /etc/apt/sources.list.d/azure-cli.list
    apt-get update -y
    apt-get install -y azure-cli
fi

# ---------- 2. DNS ----------
echo
echo "[2/7] Checking Private Endpoint name resolution..."

# Remove any old override from a previous run so we test real DNS first.
sed -i "\|${HOSTS_TAG}|d" /etc/hosts

RESOLVED_IP=$(getent ahostsv4 "$BLOB_HOST" | awk 'NR==1 {print $1}' || true)

if [[ "$RESOLVED_IP" == "$PRIVATE_IP" ]]; then
    echo "OK: Private DNS zone resolves $BLOB_HOST -> $RESOLVED_IP"
    DNS_MODE="Private DNS zone"
else
    echo "WARNING: $BLOB_HOST resolved to '${RESOLVED_IP:-nothing}', not $PRIVATE_IP."
    echo "         The Private DNS zone is probably not linked to this VNet."
    echo "         Adding an /etc/hosts override so the demo can continue."
    echo "${PRIVATE_IP} ${BLOB_HOST} ${HOSTS_TAG}" >> /etc/hosts
    RESOLVED_IP=$(getent ahostsv4 "$BLOB_HOST" | awk 'NR==1 {print $1}')
    if [[ "$RESOLVED_IP" != "$PRIVATE_IP" ]]; then
        echo "ERROR: Override failed. Got: ${RESOLVED_IP:-no address}"
        exit 1
    fi
    DNS_MODE="/etc/hosts override (fix your Private DNS link!)"
fi

# ---------- 3. Managed identity ----------
echo
echo "[3/7] Signing in with the VM managed identity..."
if ! az login --identity --output none; then
    echo "ERROR: Managed identity login failed."
    echo "Enable the VM identity and grant it 'Storage Blob Data Reader'."
    exit 1
fi

# ---------- 4. Sync script + first download ----------
echo
echo "[4/7] Installing sync script and downloading index.html..."
mkdir -p "$WEB_ROOT"

cat > "$SYNC_SCRIPT" <<EOF
#!/bin/bash
# Downloads index.html from Blob Storage via the Private Endpoint.
SA="${STORAGE_ACCOUNT}"
CONTAINER="${CONTAINER_NAME}"
DEST="${WEB_ROOT}/index.html"
EOF

cat >> "$SYNC_SCRIPT" <<'EOF'
TMP=$(mktemp)

TOKEN=$(curl -s --max-time 5 -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
  echo "$(date -Is) FAILED: could not get managed identity token"
  exit 1
fi

if curl -sf --max-time 15 \
     -H "Authorization: Bearer $TOKEN" \
     -H "x-ms-version: 2020-04-08" \
     "https://$SA.blob.core.windows.net/$CONTAINER/index.html" -o "$TMP"; then
  install -m 644 -o www-data -g www-data "$TMP" "$DEST"
  rm -f "$TMP"
  echo "$(date -Is) SUCCESS: index.html downloaded via Private Endpoint"
else
  rm -f "$TMP"
  echo "$(date -Is) FAILED: could not reach storage (blocked, timed out, or no RBAC)"
  exit 1
fi
EOF
chmod 755 "$SYNC_SCRIPT"

# Role assignments can take a few minutes; retry the first download.
for attempt in 1 2 3 4 5 6; do
    if "$SYNC_SCRIPT"; then break; fi
    if (( attempt == 6 )); then
        echo "ERROR: Download failed. Check RBAC, container/blob name, PE connectivity and DNS."
        exit 1
    fi
    echo "Retrying in 30s (attempt $attempt/6)..."
    sleep 30
done

# ---------- 5. Cron ----------
echo
echo "[5/7] Scheduling sync every 5 minutes..."
echo "*/5 * * * * root $SYNC_SCRIPT >> /var/log/sync-index.log 2>&1" > /etc/cron.d/sync-index
chmod 644 /etc/cron.d/sync-index

# ---------- 6. nginx ----------
echo
echo "[6/7] Configuring nginx on port ${WEB_PORT}..."
cat > /etc/nginx/sites-available/private-storage-demo <<NGINX
server {
    listen ${WEB_PORT} default_server;
    listen [::]:${WEB_PORT} default_server;
    server_name _;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /health {
        access_log off;
        default_type text/plain;
        return 200 "Nginx is running\n";
    }
}
NGINX

ln -sfn /etc/nginx/sites-available/private-storage-demo \
        /etc/nginx/sites-enabled/private-storage-demo
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx

# ---------- 7. Verify ----------
echo
echo "[7/7] Verifying..."
curl -fsS "http://127.0.0.1:${WEB_PORT}/health"

echo
echo "=================================================="
echo " SETUP COMPLETE"
echo "=================================================="
echo "Storage account : $STORAGE_ACCOUNT"
echo "Container       : $CONTAINER_NAME"
echo "Blob hostname   : $BLOB_HOST"
echo "Private IP      : $PRIVATE_IP"
echo "Resolved via    : $DNS_MODE"
echo "Web root        : $WEB_ROOT"
echo "Sync script     : $SYNC_SCRIPT  (cron every 5 min)"
echo
echo "Open in browser : http://<VM-PUBLIC-IP>:${WEB_PORT}"
echo
echo "Useful checks:"
echo "  getent hosts $BLOB_HOST"
echo "  sudo $SYNC_SCRIPT"
echo "  nc -vz -w 5 $PRIVATE_IP 443"
echo "  curl http://127.0.0.1:${WEB_PORT}/"
echo "=================================================="
