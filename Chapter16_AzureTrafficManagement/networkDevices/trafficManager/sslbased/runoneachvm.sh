#!/usr/bin/env bash
#
# ==============================================================================
#  NGINX Website Deployment Script (HTTP + HTTPS)
# ------------------------------------------------------------------------------
#  Deploys a three-page demo website on NGINX with a self-signed SSL
#  certificate. The VM name is supplied by the user, either as a command-line
#  argument or via an interactive prompt.
#
#  Usage:
#     sudo ./deploy_nginx.sh                 # prompts for the VM name
#     sudo ./deploy_nginx.sh "WebServer-01"  # takes the VM name as an argument
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
SSL_DIR="/etc/nginx/ssl"
WEB_ROOT="/var/www/html"
NGINX_CONF="/etc/nginx/sites-available/default"
CERT_DAYS=365

# ------------------------------------------------------------------------------
# OUTPUT HELPERS (colour, no emojis)
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_BLUE="\033[34m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_RED="\033[31m"
else
    C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

log_info()    { printf "%b[INFO]%b    %s\n"    "$C_BLUE"   "$C_RESET" "$1"; }
log_success() { printf "%b[SUCCESS]%b %s\n"    "$C_GREEN"  "$C_RESET" "$1"; }
log_warn()    { printf "%b[WARN]%b    %s\n"    "$C_YELLOW" "$C_RESET" "$1"; }
log_error()   { printf "%b[ERROR]%b   %s\n"    "$C_RED"    "$C_RESET" "$1" >&2; }

section() {
    printf "\n%b========================================%b\n" "$C_BOLD" "$C_RESET"
    printf "%b  %s%b\n"                                       "$C_BOLD" "$1" "$C_RESET"
    printf "%b========================================%b\n"   "$C_BOLD" "$C_RESET"
}

# ------------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root. Try: sudo $0"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# READ AND VALIDATE VM NAME
# ------------------------------------------------------------------------------
read_vm_name() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        # Prompt the user (read from the terminal even when run via sudo)
        printf "%bEnter the VM name:%b " "$C_BOLD" "$C_RESET"
        read -r name < /dev/tty || true
    fi

    # Trim leading/trailing whitespace
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "$name" ]]; then
        log_error "VM name cannot be empty."
        exit 1
    fi

    # Allow letters, numbers, spaces, hyphens and underscores only
    if [[ ! "$name" =~ ^[A-Za-z0-9_\ -]+$ ]]; then
        log_error "Invalid VM name. Use only letters, numbers, spaces, hyphens and underscores."
        exit 1
    fi

    VM_NAME="$name"
}

# HTML-escape a value so it is safe to embed in the generated pages
html_escape() {
    printf '%s' "$1" \
        | sed -e 's/&/\&amp;/g' \
              -e 's/</\&lt;/g'  \
              -e 's/>/\&gt;/g'  \
              -e 's/"/\&quot;/g'
}

# ------------------------------------------------------------------------------
# INSTALL PACKAGES
# ------------------------------------------------------------------------------
install_packages() {
    section "Installing Packages"
    log_info "Updating package lists..."
    apt-get update -y -qq

    log_info "Installing nginx and openssl..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx openssl
    log_success "Packages installed."
}

# ------------------------------------------------------------------------------
# CREATE SSL CERTIFICATE
# ------------------------------------------------------------------------------
create_certificate() {
    section "Creating SSL Certificate"
    mkdir -p "$SSL_DIR"

    if [[ -f "$SSL_DIR/nginx.crt" && -f "$SSL_DIR/nginx.key" ]]; then
        log_warn "Certificate already exists. Reusing existing certificate."
        return
    fi

    log_info "Generating a self-signed certificate valid for ${CERT_DAYS} days..."
    openssl req -x509 -nodes -days "$CERT_DAYS" \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/nginx.key" \
        -out "$SSL_DIR/nginx.crt" \
        -subj "/CN=localhost" 2>/dev/null

    chmod 600 "$SSL_DIR/nginx.key"
    log_success "Certificate created at $SSL_DIR."
}

# ------------------------------------------------------------------------------
# BUILD WEBSITE
# ------------------------------------------------------------------------------
build_website() {
    section "Building Website"
    mkdir -p "$WEB_ROOT"

    local vm_html server_ip
    vm_html="$(html_escape "$VM_NAME")"
    server_ip="$(hostname -I | awk '{print $1}')"

    # ----- Home Page --------------------------------------------------------
    cat > "$WEB_ROOT/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Home</title>
<style>
  body {
    margin: 0;
    font-family: Arial, sans-serif;
    background: linear-gradient(135deg, #0f172a, #2563eb);
    color: #ffffff;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
  }
  .card {
    background: rgba(255, 255, 255, 0.12);
    padding: 40px;
    border-radius: 15px;
    text-align: center;
    max-width: 650px;
    width: 90%;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
  }
  a {
    display: inline-block;
    margin: 15px;
    padding: 14px 30px;
    background: #22c55e;
    color: #ffffff;
    text-decoration: none;
    border-radius: 8px;
    font-weight: bold;
  }
  a:hover { background: #16a34a; }
</style>
</head>
<body>
  <div class="card">
    <h1>Azure NGINX Demo</h1>
    <h2>${vm_html}</h2>
    <p>Welcome to the HTTP website.</p>
    <a href="/app.html">Application Page</a>
    <a href="https://${server_ip}">Secure HTTPS Page</a>
  </div>
</body>
</html>
EOF

    # ----- Application Page -------------------------------------------------
    cat > "$WEB_ROOT/app.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Application</title>
<style>
  body {
    margin: 0;
    font-family: Arial, sans-serif;
    background: #111827;
    color: #ffffff;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
  }
  .card {
    background: #1f2937;
    padding: 40px;
    border-radius: 15px;
    text-align: center;
    max-width: 700px;
    width: 90%;
  }
  table {
    width: 100%;
    margin-top: 20px;
    border-collapse: collapse;
  }
  td {
    padding: 15px;
    border: 1px solid #555555;
  }
  a {
    display: inline-block;
    margin-top: 20px;
    padding: 12px 30px;
    background: #2563eb;
    color: #ffffff;
    text-decoration: none;
    border-radius: 8px;
  }
</style>
</head>
<body>
  <div class="card">
    <h1>Application Dashboard</h1>
    <h2>${vm_html}</h2>
    <table>
      <tr><td>Web Server</td><td>NGINX</td></tr>
      <tr><td>Protocol</td><td>HTTP</td></tr>
      <tr><td>Environment</td><td>Azure VM</td></tr>
      <tr><td>Status</td><td>Running</td></tr>
    </table>
    <a href="/">Home</a>
  </div>
</body>
</html>
EOF

    # ----- Secure HTTPS Page ------------------------------------------------
    cat > "$WEB_ROOT/secure.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Secure HTTPS</title>
<style>
  body {
    margin: 0;
    font-family: Arial, sans-serif;
    background: linear-gradient(135deg, #14532d, #16a34a, #22c55e);
    color: #ffffff;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
  }
  .card {
    background: rgba(255, 255, 255, 0.15);
    backdrop-filter: blur(12px);
    padding: 45px;
    border-radius: 18px;
    max-width: 750px;
    width: 90%;
    text-align: center;
    box-shadow: 0 15px 35px rgba(0, 0, 0, 0.4);
  }
  .lock {
    font-size: 40px;
    font-weight: bold;
    letter-spacing: 4px;
  }
  .badge {
    display: inline-block;
    background: #15803d;
    padding: 10px 22px;
    border-radius: 30px;
    font-weight: bold;
    margin: 20px;
  }
  table {
    margin: 25px auto 0;
    border-collapse: collapse;
    width: 100%;
  }
  td {
    padding: 15px;
    border: 1px solid rgba(255, 255, 255, 0.3);
  }
</style>
</head>
<body>
  <div class="card">
    <div class="lock">SECURE</div>
    <h1>HTTPS Secure Website</h1>
    <div class="badge">SSL/TLS Encryption Enabled</div>
    <h2>${vm_html}</h2>
    <table>
      <tr><td>Protocol</td><td>HTTPS</td></tr>
      <tr><td>Certificate</td><td>Self Signed</td></tr>
      <tr><td>Web Server</td><td>NGINX</td></tr>
      <tr><td>Environment</td><td>Microsoft Azure</td></tr>
      <tr><td>Connection</td><td>Encrypted</td></tr>
    </table>
  </div>
</body>
</html>
EOF

    log_success "Website pages created in $WEB_ROOT."
}

# ------------------------------------------------------------------------------
# CONFIGURE NGINX
# ------------------------------------------------------------------------------
configure_nginx() {
    section "Configuring NGINX"

    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     ${SSL_DIR}/nginx.crt;
    ssl_certificate_key ${SSL_DIR}/nginx.key;

    root ${WEB_ROOT};
    index secure.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    log_info "Validating NGINX configuration..."
    nginx -t

    log_info "Restarting and enabling NGINX..."
    systemctl restart nginx
    systemctl enable nginx >/dev/null 2>&1
    log_success "NGINX configured and running."
}

# ------------------------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------------------------
print_summary() {
    local server_ip
    server_ip="$(hostname -I | awk '{print $1}')"

    section "Deployment Completed"
    printf "  %-12s : http://%s/\n"       "HTTP Home"  "$server_ip"
    printf "  %-12s : http://%s/app.html\n" "HTTP App"  "$server_ip"
    printf "  %-12s : https://%s/\n"      "HTTPS Page" "$server_ip"
    printf "  %-12s : %s\n"               "VM Name"    "$VM_NAME"
    printf "========================================\n"
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
    require_root
    read_vm_name "${1:-}"

    log_info "Starting deployment for VM: ${VM_NAME}"

    install_packages
    create_certificate
    build_website
    configure_nginx
    print_summary

    log_success "All done."
}

main "$@"