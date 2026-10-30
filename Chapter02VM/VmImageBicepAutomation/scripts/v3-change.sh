#!/bin/bash
set -euo pipefail

DEBIAN_FRONTEND=noninteractive apt-get install -y htop

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    add_header X-Image-Version "1.2.0" always;
    location / { try_files $uri $uri/ =404; }
    location = /health { default_type text/plain; return 200 "OK\n"; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.2.0</title></head>
<body style="font-family:sans-serif;background:#6a1b9a;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.2.0</h2>
  <p>Change #2: <code>X-Image-Version</code> header + <a style="color:#fff" href="/about.html">About page</a> + htop</p>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

cat > /var/www/html/about.html <<'EOF'
<!doctype html>
<html><body style="font-family:sans-serif;padding:40px">
  <h1>About</h1>
  <p>This VM was deployed from Azure Compute Gallery image <b>1.2.0</b> via Bicep.</p>
</body></html>
EOF

echo "1.2.0" > /var/www/html/version.txt

nginx -t
systemctl restart nginx
