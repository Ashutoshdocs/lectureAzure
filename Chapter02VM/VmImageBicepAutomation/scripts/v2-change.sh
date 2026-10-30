#!/bin/bash
set -euo pipefail

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    location / { try_files $uri $uri/ =404; }
    location = /health { default_type text/plain; return 200 "OK\n"; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.1.0</title></head>
<body style="font-family:sans-serif;background:#2e7d32;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.1.0</h2>
  <p>Change #1: new theme + <code>/health</code> endpoint</p>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

echo "1.1.0" > /var/www/html/version.txt

nginx -t
systemctl restart nginx
