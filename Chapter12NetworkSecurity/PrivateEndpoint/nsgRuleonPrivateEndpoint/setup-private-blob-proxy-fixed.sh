#!/usr/bin/env bash
set -Eeuo pipefail

# Azure VM -> Nginx -> local Python proxy -> Azure Blob Private Endpoint
# Ubuntu 22.04 / 24.04
# Run: sudo bash setup-private-blob-proxy.sh

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0"
  exit 1
fi

echo "=================================================="
echo " Azure VM -> Blob Storage Private Endpoint Proxy"
echo "=================================================="

read -rp "Storage Account name: " STORAGE_ACCOUNT
read -rp "Blob container name: " CONTAINER_NAME
read -rp "Storage Blob Private Endpoint IP: " PRIVATE_IP
read -rp "Nginx web port [30080]: " WEB_PORT
WEB_PORT="${WEB_PORT:-30080}"

# Validate inputs
if [[ ! "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo "ERROR: Storage Account name must be 3-24 lowercase letters/digits."
  exit 1
fi

if [[ ! "$CONTAINER_NAME" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]]; then
  echo "ERROR: Invalid container name (use 3-63 lowercase letters, digits, or hyphens; start/end with letter or digit)."
  exit 1
fi

if [[ ! "$WEB_PORT" =~ ^[0-9]+$ ]] || (( WEB_PORT < 1 || WEB_PORT > 65535 )); then
  echo "ERROR: Invalid port."
  exit 1
fi

python3 - "$PRIVATE_IP" <<'PY'
import ipaddress
import sys

try:
    ip = ipaddress.ip_address(sys.argv[1])
    if ip.version != 4 or not ip.is_private or ip.is_loopback or ip.is_link_local:
        raise ValueError("must be a private IPv4 address")
except ValueError as exc:
    print(f"ERROR: {exc}")
    sys.exit(1)
PY

BLOB_HOST="${STORAGE_ACCOUNT}.blob.core.windows.net"
HOSTS_TAG="# AZURE_PRIVATE_BLOB_PROXY"
PROXY_DIR="/opt/azure-blob-proxy"

echo
echo "[1/6] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx python3 curl ca-certificates

echo
echo "[2/6] Configuring and verifying Blob hostname resolution..."
# Remove only a previous entry created by this script.
sed -i "\|${HOSTS_TAG} ${BLOB_HOST}$|d" /etc/hosts

CURRENT_IP="$(getent ahostsv4 "$BLOB_HOST" | awk 'NR==1 {print $1}' || true)"
if [[ "$CURRENT_IP" != "$PRIVATE_IP" ]]; then
  echo "DNS currently resolves to '${CURRENT_IP:-nothing}', not $PRIVATE_IP."
  echo "Adding a lab-only /etc/hosts override."
  echo "For production, configure the Azure Private DNS zone and VNet link."
  echo "${PRIVATE_IP} ${BLOB_HOST} ${HOSTS_TAG}" >> /etc/hosts
fi

RESOLVED_IP="$(getent ahostsv4 "$BLOB_HOST" | awk 'NR==1 {print $1}' || true)"
if [[ "$RESOLVED_IP" != "$PRIVATE_IP" ]]; then
  echo "ERROR: $BLOB_HOST resolved to '${RESOLVED_IP:-nothing}', expected $PRIVATE_IP."
  exit 1
fi
echo "Verified: $BLOB_HOST -> $RESOLVED_IP"

echo
echo "[3/6] Installing the local managed-identity Blob proxy..."
install -d -m 0755 "$PROXY_DIR"

cat > "$PROXY_DIR/blob_proxy.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ACCOUNT = os.environ["STORAGE_ACCOUNT"]
CONTAINER = os.environ["CONTAINER_NAME"]
BLOB_HOST = f"{ACCOUNT}.blob.core.windows.net"
BLOB_URL = (
    f"https://{BLOB_HOST}/"
    f"{urllib.parse.quote(CONTAINER, safe='')}/index.html"
)
IMDS_URL = (
    "http://169.254.169.254/metadata/identity/oauth2/token"
    "?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F"
)

token_cache = {"token": None, "expires": 0}

# Bypass environment proxy variables so Storage connects directly to the
# hostname resolved to the Private Endpoint IP through DNS or /etc/hosts.
DIRECT_OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({})
)

def get_token():
    now = time.time()
    if token_cache["token"] and now < token_cache["expires"] - 120:
        return token_cache["token"]

    request = urllib.request.Request(
        IMDS_URL,
        headers={"Metadata": "true"},
    )
    with DIRECT_OPENER.open(request, timeout=5) as response:
        payload = json.loads(response.read().decode("utf-8"))

    token = payload.get("access_token")
    if not token:
        raise RuntimeError("Managed identity response did not contain a token")

    try:
        lifetime = int(payload.get("expires_in", "3600"))
    except (TypeError, ValueError):
        lifetime = 3600

    token_cache["token"] = token
    token_cache["expires"] = now + lifetime
    return token

class Handler(BaseHTTPRequestHandler):
    server_version = "AzureBlobPrivateProxy/1.0"

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path

        if path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"Proxy is running\n")
            return

        # This is intentionally a fixed-blob proxy, not an open proxy.
        if path not in ("/", "/index.html"):
            self.send_error(404, "Only / and /index.html are available")
            return

        try:
            token = get_token()
            upstream_request = urllib.request.Request(
                BLOB_URL,
                headers={
                    "Authorization": f"Bearer {token}",
                    "x-ms-version": "2020-04-08",
                    "Accept": "text/html,*/*",
                },
                method="GET",
            )

            with DIRECT_OPENER.open(upstream_request, timeout=20) as upstream:
                content = upstream.read()
                content_type = upstream.headers.get(
                    "Content-Type", "text/html; charset=utf-8"
                )
                self.send_response(upstream.status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                self.wfile.write(content)

        except urllib.error.HTTPError as exc:
            # Do not disclose token values or upstream response contents.
            self.log_error("Blob Storage returned HTTP %s", exc.code)
            self.send_error(
                502,
                "Blob Storage request failed; check blob name, RBAC and Storage settings",
            )
        except Exception as exc:
            self.log_error("Proxy request failed: %s", type(exc).__name__)
            self.send_error(
                502,
                "Could not retrieve page; check managed identity and private connectivity",
            )

    def log_message(self, fmt, *args):
        print(
            "%s - %s" % (self.address_string(), fmt % args),
            flush=True,
        )

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
PY

chmod 0755 "$PROXY_DIR/blob_proxy.py"

cat > /etc/systemd/system/azure-blob-proxy.service <<EOF
[Unit]
Description=Azure Blob Storage Managed Identity Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
Environment="CONTAINER_NAME=${CONTAINER_NAME}"
ExecStart=/usr/bin/python3 ${PROXY_DIR}/blob_proxy.py
Restart=on-failure
RestartSec=3
User=www-data
Group=www-data
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

echo
echo "[4/6] Configuring Nginx on port ${WEB_PORT}..."
cat > /etc/nginx/sites-available/azure-blob-private-proxy <<EOF
server {
    listen ${WEB_PORT} default_server;
    listen [::]:${WEB_PORT} default_server;
    server_name _;

    location = /health {
        proxy_pass http://127.0.0.1:8080/health;
        proxy_set_header Host \$host;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
EOF

ln -sfn /etc/nginx/sites-available/azure-blob-private-proxy \
  /etc/nginx/sites-enabled/azure-blob-private-proxy
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl daemon-reload
systemctl enable --now azure-blob-proxy
systemctl enable nginx
systemctl restart nginx

echo
echo "[5/6] Checking local proxy health..."
for attempt in {1..10}; do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8080/health

echo
echo "[6/6] Testing Nginx -> proxy -> Blob Storage..."
if curl -fsS --max-time 25 "http://127.0.0.1:${WEB_PORT}/" -o /dev/null; then
  echo "SUCCESS: Nginx retrieved index.html from Blob Storage."
else
  echo "ERROR: Page retrieval failed."
  echo "Proxy logs: sudo journalctl -u azure-blob-proxy -n 60 --no-pager"
  echo "Check managed identity, Storage Blob Data Reader RBAC, container/blob name,"
  echo "Private Endpoint connectivity, Storage firewall and private DNS."
  exit 1
fi

echo
echo "=================================================="
echo " SETUP COMPLETE"
echo "=================================================="
echo "Storage account : $STORAGE_ACCOUNT"
echo "Container       : $CONTAINER_NAME"
echo "Blob hostname   : $BLOB_HOST"
echo "Private IP      : $PRIVATE_IP"
echo "Resolved IP     : $RESOLVED_IP"
echo "Nginx port      : $WEB_PORT"
echo "Open            : http://<VM-PUBLIC-IP>:${WEB_PORT}"
echo
echo "Useful checks:"
echo "  getent hosts $BLOB_HOST"
echo "  nc -vz $PRIVATE_IP 443"
echo "  curl -v http://127.0.0.1:${WEB_PORT}/"
echo "  sudo journalctl -u azure-blob-proxy -f"
echo "=================================================="
