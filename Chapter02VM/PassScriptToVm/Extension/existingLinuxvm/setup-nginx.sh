#!/bin/bash
# setup-nginx.sh
# Installs nginx and publishes a simple demo page on an existing Ubuntu VM.
# Intended to be run by Azure Custom Script Extension for Linux.

set -Eeuo pipefail

WEB_ROOT="/var/www/html"
PAGE_PATH="${WEB_ROOT}/index.html"
export DEBIAN_FRONTEND=noninteractive

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

on_error() {
    local exit_code=$?
    log "ERROR: command failed near line ${1}; exit code: ${exit_code}"
    exit "${exit_code}"
}
trap 'on_error ${LINENO}' ERR

if [[ "${EUID}" -ne 0 ]]; then
    log "Run this script as root (the Azure Custom Script Extension normally does this)."
    exit 1
fi

log "Updating Ubuntu package index..."
apt-get update -y

log "Installing nginx..."
apt-get install -y nginx

log "Creating web root..."
install -d -m 0755 "${WEB_ROOT}"

HOST_NAME="$(hostname)"
DEPLOYED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"

log "Writing demo page to ${PAGE_PATH}..."
cat > "${PAGE_PATH}" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Azure Custom Script Extension - Linux Demo</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: Arial, sans-serif;
      background: linear-gradient(135deg, #009639, #e95420);
    }
    .card {
      background: #fff;
      padding: 40px;
      margin: 20px;
      border-radius: 14px;
      box-shadow: 0 10px 30px rgba(0,0,0,.2);
      text-align: center;
      max-width: 650px;
    }
    h1 { color: #009639; }
    p { color: #444; line-height: 1.6; }
    .meta { color: #777; font-size: .9rem; margin-top: 24px; }
  </style>
</head>
<body>
  <main class="card">
    <h1>&#9989; nginx is running</h1>
    <p>nginx was installed and configured automatically.</p>
    <p>Script executed using <strong>Azure Custom Script Extension for Linux</strong>.</p>
    <div class="meta">Server: ${HOST_NAME}<br>Deployment time: ${DEPLOYED_AT}</div>
  </main>
</body>
</html>
EOF

log "Enabling nginx at boot..."
systemctl enable nginx

log "Restarting nginx..."
systemctl restart nginx

log "Checking nginx service..."
systemctl is-active --quiet nginx

log "Success: nginx is installed and running."
log "Test locally with: curl -I http://localhost"
exit 0
