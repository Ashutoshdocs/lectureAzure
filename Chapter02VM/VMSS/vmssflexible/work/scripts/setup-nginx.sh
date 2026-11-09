#!/usr/bin/env bash
set -euo pipefail

# Azure VMSS Flexible demo: install Nginx and publish a hostname-aware page.
HOSTNAME_VALUE="$(hostname -f 2>/dev/null || hostname)"
PRIVATE_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
PUBLIC_IP="$(curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || echo 'Not detected')"
STAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx curl

mkdir -p /var/www/html
cat >/var/www/html/index.html <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Azure VMSS Flexible Demo</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;font-family:Inter,Segoe UI,Arial,sans-serif;color:#eef4ff;
background:radial-gradient(circle at 15% 15%,#254b83 0,transparent 35%),
radial-gradient(circle at 85% 80%,#542a78 0,transparent 35%),#081426;
display:grid;place-items:center;padding:28px}
.card{width:min(760px,100%);padding:42px;border:1px solid #ffffff24;border-radius:28px;
background:#ffffff0d;box-shadow:0 25px 80px #0008;backdrop-filter:blur(12px)}
.eyebrow{display:inline-flex;gap:9px;align-items:center;padding:8px 13px;border-radius:99px;
background:#32d6a51c;color:#7ef0cb;font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase}
.dot{width:8px;height:8px;border-radius:50%;background:#44e0ad;box-shadow:0 0 14px #44e0ad}
h1{font-size:clamp(32px,6vw,54px);line-height:1.05;margin:22px 0 12px}
h1 span{color:#78b7ff}
.sub{color:#b8c8df;font-size:17px;line-height:1.6;margin:0 0 28px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}
.tile{padding:18px;border-radius:17px;background:#07101f99;border:1px solid #ffffff17}
.label{color:#8da5c5;font-size:12px;text-transform:uppercase;letter-spacing:.1em;margin-bottom:9px}
.value{font-size:17px;font-weight:700;overflow-wrap:anywhere}
.footer{margin-top:25px;color:#8da5c5;font-size:12px;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}
</style>
</head>
<body>
<main class="card">
  <div class="eyebrow"><i class="dot"></i> Azure compute • Nginx online</div>
  <h1>Hello from <span>Azure</span></h1>
  <p class="sub">This page is served by Nginx. Refresh the page or test another instance to see which virtual machine handled your request.</p>
  <section class="grid">
    <div class="tile"><div class="label">VM hostname</div><div class="value">${HOSTNAME_VALUE}</div></div>
    <div class="tile"><div class="label">Private IP</div><div class="value">${PRIVATE_IP:-Unknown}</div></div>
    <div class="tile"><div class="label">Public IP (if available)</div><div class="value">${PUBLIC_IP}</div></div>
    <div class="tile"><div class="label">Provisioned at</div><div class="value">${STAMP}</div></div>
  </section>
  <div class="footer"><span>VMSS Flexible Orchestration lab</span><span>Instance identity demo</span></div>
</main>
</body>
</html>
HTML

cat >/etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    location / {
        try_files $uri $uri/ =404;
        add_header Cache-Control "no-store";
    }
}
NGINX
nginx -t
systemctl enable nginx
systemctl restart nginx
echo "Nginx demo page deployed on ${HOSTNAME_VALUE}"
