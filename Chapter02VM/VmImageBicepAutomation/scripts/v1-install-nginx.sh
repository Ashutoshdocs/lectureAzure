#!/bin/bash
set -euo pipefail

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

# Site config: SSI lets the page show the hostname of the VM serving it
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    location / { try_files $uri $uri/ =404; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.0.0</title></head>
<body style="font-family:sans-serif;background:#1f4e79;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.0.0</h2>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

echo "1.0.0" > /var/www/html/version.txt

nginx -t
systemctl enable nginx
systemctl restart nginx
