#!/usr/bin/env bash
set -e

# Azure VM Run Command demo
# Installs Nginx and deploys a beautiful webpage on an already-running VM.

apt-get update -y
apt-get install -y nginx

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Azure Run Command Demo</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{
 min-height:100vh;display:flex;align-items:center;justify-content:center;
 padding:24px;font-family:Arial,Helvetica,sans-serif;color:white;
 background:linear-gradient(135deg,#0f172a,#1d4ed8,#38bdf8)
}
.card{
 width:min(900px,100%);padding:55px 45px;text-align:center;
 border-radius:28px;background:rgba(255,255,255,.12);
 border:1px solid rgba(255,255,255,.25);
 box-shadow:0 25px 70px rgba(0,0,0,.35);
 backdrop-filter:blur(12px)
}
.badge{
 display:inline-block;padding:9px 18px;border-radius:999px;
 background:rgba(255,255,255,.18);font-size:14px;
 letter-spacing:1px;margin-bottom:22px
}
h1{font-size:clamp(38px,7vw,72px);margin-bottom:18px}
h1 span{color:#67e8f9}
p{font-size:21px;line-height:1.7;color:#e0f2fe;margin:12px auto;max-width:720px}
.flow{margin:32px auto 0;display:flex;justify-content:center;gap:12px;flex-wrap:wrap}
.step{
 padding:12px 18px;border-radius:14px;background:rgba(255,255,255,.13);
 border:1px solid rgba(255,255,255,.18);font-weight:bold
}
.footer{margin-top:34px;font-size:14px;color:#bae6fd}
</style>
</head>
<body>
<main class="card">
<div class="badge">☁ AZURE RUN COMMAND DEMO</div>
<h1>Page deployed <span>via az vm run-command</span></h1>
<p>
This Nginx web server and webpage were configured remotely on an
already-running Azure VM using Azure Run Command.
</p>
<div class="flow">
<div class="step">Azure CLI</div><div class="step">→</div>
<div class="step">Run Command</div><div class="step">→</div>
<div class="step">Nginx</div><div class="step">→</div>
<div class="step">Web Page</div>
</div>
<div class="footer">
✓ Existing VM &nbsp; | &nbsp; ✓ Remote execution &nbsp; | &nbsp; ✓ Nginx deployed
</div>
</main>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx

echo "Azure Run Command Nginx demo completed successfully."
systemctl is-active nginx
curl -I http://localhost
