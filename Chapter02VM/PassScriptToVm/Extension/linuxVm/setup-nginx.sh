#!/bin/bash
# ==============================================================
#  setup-nginx.sh
# --------------------------------------------------------------
#  Installs nginx and publishes a demo web page on an Azure VM.
#
#  Meant to be run by the Azure Custom Script Extension for Linux
#  when an Ubuntu VM is deployed. The script:
#    1. Updates the package index
#    2. Installs the nginx web server
#    3. Creates a styled index.html in /var/www/html
#    4. Enables and restarts the nginx service
#
#  Course : AZ-104 - Custom Script Extensions demo (Linux)
#  Runs as: root (through the Custom Script Extension agent)
# ==============================================================

set -euo pipefail

# --------------------------------------------------------------
# Settings
# --------------------------------------------------------------
WEB_ROOT="/var/www/html"
PAGE_PATH="${WEB_ROOT}/index.html"
export DEBIAN_FRONTEND=noninteractive   # no interactive prompts during install

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

trap 'log "ERROR: setup failed on line ${LINENO}"; exit 1' ERR

# --------------------------------------------------------------
# Step 1 - Update the package index
# --------------------------------------------------------------
log "Updating package index..."
apt-get update -y

# --------------------------------------------------------------
# Step 2 - Install nginx
# --------------------------------------------------------------
log "Installing nginx..."
apt-get install -y nginx

# --------------------------------------------------------------
# Step 3 - Build and save the HTML page
# --------------------------------------------------------------
log "Creating demo page at ${PAGE_PATH}..."
HOST_NAME="$(hostname)"
DEPLOYED="$(date '+%Y-%m-%d %H:%M:%S')"

cat > "${PAGE_PATH}" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Custom Script Extensions Demo - Linux</title>
  <style>
    body {
      margin: 0; height: 100vh;
      display: flex; align-items: center; justify-content: center;
      font-family: 'Ubuntu', 'Segoe UI', Arial, sans-serif;
      background: linear-gradient(135deg, #009639, #e95420);
    }
    .card {
      background: #ffffff; padding: 40px 50px; border-radius: 12px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2); text-align: center; max-width: 600px;
    }
    h1 { color: #009639; margin-top: 0; }
    p  { color: #444; }
    .meta { font-size: 0.9em; color: #888; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>&#9989; nginx is running</h1>
    <p>We now have nginx running as the web server on this machine.</p>
    <p>Installed automatically by the <strong>Azure Custom Script Extension for Linux</strong>.</p>
    <div class="meta">Server: ${HOST_NAME} &middot; Deployed: ${DEPLOYED}</div>
  </div>
</body>
</html>
EOF

# --------------------------------------------------------------
# Step 4 - Enable and restart nginx
# --------------------------------------------------------------
log "Enabling and restarting nginx..."
systemctl enable nginx
systemctl restart nginx

log "Done. Browse to http://<public-ip>"
exit 0
