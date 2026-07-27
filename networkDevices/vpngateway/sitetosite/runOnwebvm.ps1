#!/bin/bash
set -e

echo "======================================"
echo " Installing NGINX"
echo "======================================"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y nginx

systemctl enable nginx
systemctl start nginx

echo "======================================"
echo " Creating Dashboard Script"
echo "======================================"

cat >/usr/local/bin/dashboard.sh <<'EOF'
#!/bin/bash
# Generates two files every run:
#   /var/www/html/dashboard.txt  -> plain text (served to curl/wget)
#   /var/www/html/index.html     -> styled page (served to browsers)

# ---- collect stats ----
HOST=$(hostname)
OS=$(. /etc/os-release; echo "$PRETTY_NAME")
KERNEL=$(uname -r)
IP=$(hostname -I | awk '{print $1}')
UPTIME=$(uptime -p | sed 's/up //')
CPU=$(top -bn1 | awk '/Cpu\(s\)/{printf "%.1f%%",100-$8}')
MEM=$(free | awk '/Mem:/{printf "%.0f%%",$3/$2*100}')
DISK=$(df -h / | awk 'NR==2{print $5}')
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')
REGION="Central India"

# ---- box helpers (W = inner width) ----
W=76
TOP="╔$(printf '═%.0s' $(seq 1 $W))╗"
MID="╠$(printf '═%.0s' $(seq 1 $W))╣"
BOT="╚$(printf '═%.0s' $(seq 1 $W))╝"

center(){ local s="$1" n=${#1} l; l=$(((W-n)/2)); printf "║%*s%s%*s║" "$l" '' "$s" "$((W-n-l))" ''; }
row(){ local v="$2"; ((${#v}>W-22)) && v="${v:0:$((W-25))}..."; printf "║  %-18s: %-*s║" "$1" "$((W-22))" "$v"; }
head_(){ printf "║  %-*s║" "$((W-2))" "$1"; }
ul(){ printf "║  %-*s║" "$((W-2))" "$(printf '%*s' $((W-4)) '' | tr ' ' '-')"; }
blank(){ printf "║%*s║" "$W" ''; }

read -r -d '' BODY <<TXT || true
$TOP
$(center "MICROSOFT AZURE - PRIVATE WEB SERVER")
$(center "Site-to-Site VPN Demonstration")
$MID
$(blank)
$(head_ "Server Information")
$(ul)
$(row "Hostname" "$HOST")
$(row "Operating System" "$OS")
$(row "Kernel Version" "$KERNEL")
$(row "Azure Region" "$REGION")
$(blank)
$(head_ "Network Information")
$(ul)
$(row "Private IP" "$IP")
$(row "Public IP" "Not Assigned")
$(row "Virtual Network" "10.0.0.0/16")
$(row "Subnet" "WebSubnet")
$(blank)
$(head_ "Site-to-Site VPN Status")
$(ul)
$(row "Tunnel Status" "CONNECTED")
$(row "VPN Type" "IPSec IKEv2")
$(row "Encryption" "AES-256")
$(row "Authentication" "Pre-Shared Key")
$(blank)
$(head_ "Connected Site")
$(ul)
$(row "Company Network" "172.16.0.0/16")
$(row "Azure Network" "10.0.0.0/16")
$(row "Access Method" "Site-to-Site VPN")
$(blank)
$(head_ "Live Server Statistics")
$(ul)
$(row "Uptime" "$UPTIME")
$(row "CPU Usage" "$CPU")
$(row "Memory Usage" "$MEM")
$(row "Disk Usage" "$DISK")
$(row "Current Time" "$NOW")
$(blank)
$MID
$(head_ "[OK] Azure VM has NO Public IP")
$(head_ "[OK] Accessible ONLY through Site-to-Site VPN")
$(head_ "[OK] Communication is encrypted using IPSec")
$(head_ "[OK] Azure VPN Gateway <-> Company Network")
$BOT
TXT

# ---- write plain-text version (curl / wget) ----
printf '%s\n' "$BODY" > /var/www/html/dashboard.txt

# ---- write HTML version (browser) ----
# escape for HTML, then colorize status markers (spans add no visible width)
PRE=$(printf '%s' "$BODY" \
  | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' \
  | sed 's/\[OK\]/<span class="ok">[OK]<\/span>/g; s/CONNECTED/<span class="ok">CONNECTED<\/span>/g')

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="5">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Azure Site-to-Site VPN Dashboard</title>
<style>
  :root{--bg:#0f172a;--fg:#00ff88;--accent:#4fc3f7;}
  *{box-sizing:border-box;}
  body{margin:0;min-height:100vh;
       background:radial-gradient(1200px 600px at 50% -10%,#15213b,#0f172a);
       color:var(--fg);font-family:"Cascadia Code","Fira Code",Consolas,"DejaVu Sans Mono",monospace;
       display:flex;flex-direction:column;align-items:center;padding:24px;}
  h1{color:var(--accent);font-weight:600;letter-spacing:.5px;margin:8px 0 4px;text-align:center;}
  .sub{color:#9fb3c8;margin-bottom:18px;font-size:14px;text-align:center;}
  .card{background:rgba(2,6,23,.6);border:1px solid #1e293b;border-radius:12px;
        box-shadow:0 10px 40px rgba(0,0,0,.45);padding:20px 24px;overflow:auto;max-width:100%;}
  pre{margin:0;font-size:15px;line-height:1.35;white-space:pre;}
  .ok{color:#22c55e;font-weight:600;}
  .footer{color:#64748b;margin-top:16px;font-size:13px;text-align:center;}
  code{color:#93c5fd;}
</style>
</head>
<body>
  <h1>Microsoft Azure &mdash; Private Web Server</h1>
  <div class="sub">Site-to-Site VPN Demonstration &middot; auto-refresh every 5s</div>
  <div class="card"><pre>$PRE</pre></div>
  <div class="footer">Browsers see this styled page &middot; <code>curl</code> receives plain text &middot; updated $NOW</div>
</body>
</html>
HTML
EOF

chmod +x /usr/local/bin/dashboard.sh
mkdir -p /var/www/html
/usr/local/bin/dashboard.sh   # populate immediately

echo "======================================"
echo " Creating Dashboard Service"
echo "======================================"

cat >/etc/systemd/system/vpndashboard.service <<EOF
[Unit]
Description=Azure VPN Dashboard
After=network.target

[Service]
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/dashboard.sh; sleep 5; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpndashboard
systemctl start vpndashboard

echo "======================================"
echo " Configuring NGINX (curl vs browser)"
echo "======================================"

cat >/etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    charset utf-8;

    location = / {
        default_type text/html;
        # CLI tools get the plain-text box; everything else gets the HTML page
        if ($http_user_agent ~* (curl|wget|libcurl|httpie|python-requests|Go-http|PowerShell|Wget)) {
            rewrite ^ /dashboard.txt last;
        }
        try_files /index.html =404;
    }

    location = /dashboard.txt {
        default_type text/plain;
    }
}
NGINX

nginx -t
systemctl reload nginx

IP=$(hostname -I | awk '{print $1}')
echo "======================================"
echo " Dashboard Ready"
echo "======================================"
echo
echo "Browser : http://$IP/"
echo "Terminal: curl http://$IP/"
echo "Raw text: curl http://$IP/dashboard.txt"
echo
echo "Both refresh every 5 seconds."
