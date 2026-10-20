#!/bin/bash

set -e

echo "Updating packages..."
apt-get update

echo "Installing Nginx..."
apt-get install -y nginx

systemctl enable nginx
systemctl start nginx

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Azure Load Balancer Demo - VM1</title>

<style>
body{
    margin:0;
    font-family:Segoe UI,Arial;
    background:linear-gradient(135deg,#0f2027,#203a43,#2c5364);
    color:white;
}

.header{
    background:#0057b8;
    padding:25px;
    text-align:center;
    font-size:40px;
    font-weight:bold;
}

.container{
    width:85%;
    margin:auto;
    padding:30px;
}

.card{
    background:white;
    color:#333;
    border-radius:15px;
    padding:30px;
    margin-top:25px;
    box-shadow:0 0 20px rgba(0,0,0,.4);
}

.vm{
    font-size:55px;
    color:#0057b8;
    font-weight:bold;
    text-align:center;
}

h2{
    color:#0057b8;
}

.footer{
    margin-top:40px;
    text-align:center;
    padding:20px;
    background:#0057b8;
    color:white;
}
</style>

</head>

<body>

<div class="header">
Microsoft Azure Load Balancer Demonstration
</div>

<div class="container">

<div class="card">

<div class="vm">
YOU ARE CONNECTED TO<br>
AZURE VM 01
</div>

<hr>

<h2>Azure Load Balancer Practical Demonstration</h2>

<p>
Welcome to Azure Virtual Machine 01. This webpage has been intentionally designed to verify that Azure Load Balancer is distributing incoming client requests across multiple backend virtual machines.
</p>

<p>
Azure Load Balancer operates at Layer 4 of the OSI Model. Unlike Application Gateway, it does not inspect HTTP headers, cookies, URLs, or application content. Instead, it forwards TCP and UDP packets based on configurable load-balancing rules.
</p>

<p>
During this demonstration, multiple virtual machines are placed inside a Backend Pool. Every time a client refreshes the browser, Azure evaluates the connection using its five-tuple hash algorithm consisting of:
</p>

<ul>
<li>Source IP Address</li>
<li>Destination IP Address</li>
<li>Source Port</li>
<li>Destination Port</li>
<li>Protocol (TCP/UDP)</li>
</ul>

<p>
The result is a predictable backend selection. If Session Persistence is disabled, new connections can reach different virtual machines. If Client IP affinity is enabled, the same client usually reaches the same backend.
</p>

<p>
Health Probes continuously monitor every backend VM. If this server stops responding, Azure immediately removes it from the load balancing rotation without administrator intervention.
</p>

<p>
This demonstration is frequently used during Azure Administrator (AZ-104), Azure Architect (AZ-305), and Azure Networking training to explain highly available infrastructure.
</p>

<h2>Current Backend</h2>

<h1 style="color:#0057b8;text-align:center;">
AZURE VM 01
</h1>

</div>

</div>

<div class="footer">
Azure Load Balancer Demo • Backend Server VM01
</div>

</body>
</html>
EOF

chmod 644 /var/www/html/index.html

systemctl restart nginx

echo "Deployment Successful!"
