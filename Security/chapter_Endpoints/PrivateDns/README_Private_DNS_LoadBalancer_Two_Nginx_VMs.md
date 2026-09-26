# Azure Private DNS + Load Balancer + Two Nginx VMs
## End-to-End Teaching Lab with Separate Web Pages

> This lab follows the supplied architecture diagram: one VNet, two backend VMs in a `web-pool`, an Azure Load Balancer with a Public IP, a `vmclient`, and an Azure Private DNS Zone.

---

# 1. 🎯 Lab Objective

We will build the following teaching scenario:

```text
                    Azure VNet
                  myrg-vnet
                 10.0.0.0/16
                       |
          +------------+-------------+
          |                          |
          |                    vmclient
          |                          |
          |                     DNS Query
          |                          |
          |                          |
          |      Public Load Balancer|
          |      PIP: <LB-PUBLIC-IP> |
          |              |            |
          |              v            |
          |          web-pool         |
          |         /        \         |
          |        /          \        |
          |       v            v       |
          |     VM1           VM2      |
          |    APP-01        APP-02    |
          |      |              |      |
          |    Nginx          Nginx    |
          |      |              |      |
          +------+--------------+------+

Private DNS Zone
learninghubtech.com

www.learninghubtech.com
          |
          v
      <LB-PUBLIC-IP>
```

The two backend VMs will serve **different HTML pages**.

### VM1

```text
╔══════════════════════════════╗
║      LEARNING HUB TECH       ║
║                              ║
║       APP SERVER 01          ║
║                              ║
║   Response from Backend 01   ║
╚══════════════════════════════╝
```

### VM2

```text
╔══════════════════════════════╗
║      LEARNING HUB TECH       ║
║                              ║
║       APP SERVER 02          ║
║                              ║
║   Response from Backend 02   ║
╚══════════════════════════════╝
```

When students repeatedly open:

```text
http://www.learninghubtech.com
```

the Azure Load Balancer can send requests to either backend VM.

This makes it easy to demonstrate:

- Private DNS
- DNS records
- VNet links
- Public Load Balancer
- Backend pool
- Health probes
- Load balancing
- Nginx
- Multiple backend servers
- Failover behavior

---

# 2. ⚠️ Important Architecture Note

The supplied architecture shows:

```text
Private DNS Zone
       |
       | A record
       v
www.learninghubtech.com
       |
       v
Public Load Balancer IP
```

Therefore, this lab demonstrates a **Private DNS Zone containing a DNS record for the Load Balancer's public IP**.

The DNS zone itself is private and is linked to the VNet, but the IP returned by the record is a **public Load Balancer frontend IP**.

Therefore:

```text
Private DNS
    ≠
Private IP automatically
```

A Private DNS Zone controls **name resolution**.

Whether traffic is private or public depends on the IP address returned and the network path.

For a completely private architecture, an internal Load Balancer/private IP would normally be used instead.

---

# 3. 🧠 Architecture Components

| Component | Example |
|---|---|
| Resource Group | `myrg` |
| VNet | `myrg-vnet` |
| VNet CIDR | `10.0.0.0/16` |
| Client VM | `vmclient` |
| Backend VM 1 | `vmapp01` |
| Backend VM 2 | `vmapp02` |
| Backend pool | `web-pool` |
| Load Balancer | `lbhlb` |
| Public IP | `40.89.249.236` in the diagram |
| Private DNS Zone | `learninghubtech.com` |
| DNS record | `www` |
| Backend software | Nginx |

> Do not hard-code `40.89.249.236` unless that is actually the IP assigned to your Load Balancer. Retrieve the current Public IP from Azure.

---

# 4. 🌐 Network Address Plan

```text
VNet
10.0.0.0/16
│
├── Application Subnet
│   10.0.1.0/24
│   │
│   ├── vmapp01
│   └── vmapp02
│
└── Client Subnet
    10.0.2.0/24
    │
    └── vmclient
```

The exact subnet names and CIDRs can be changed if your existing environment already exists.

---

# 5. 🔑 Teaching Concept

The complete request flow is:

```text
Browser
   |
   | http://www.learninghubtech.com
   |
   v
Private DNS
   |
   | A record
   v
Load Balancer Public IP
   |
   v
Azure Load Balancer
   |
   | Backend Pool
   |
   +------------------+
   |                  |
   v                  v
 VMAPP01            VMAPP02
 Nginx              Nginx
 APP-01             APP-02
```

The DNS step and Load Balancer step are separate.

### DNS answers:

```text
"What IP belongs to www.learninghubtech.com?"
```

### Load Balancer answers:

```text
"Which healthy backend VM should receive this request?"
```

---

# 6. 🚀 Deployment Variables

Run from Azure Cloud Shell or a machine with Azure CLI.

```bash
LOCATION="centralindia"

RG="myrg"

VNET="myrg-vnet"

APP_SUBNET="app-subnet"
CLIENT_SUBNET="client-subnet"

VM1="vmapp01"
VM2="vmapp02"
CLIENT="vmclient"

LB="lbhlb"
PIP="lbhlb-pip"

BACKEND_POOL="web-pool"

DNS_ZONE="learninghubtech.com"
DNS_RECORD="www"
```

Login:

```bash
az login
```

Check subscription:

```bash
az account show --output table
```

---

# 7. 🏢 Step 1 — Create Resource Group

```bash
az group create \
  --name $RG \
  --location $LOCATION
```

Verify:

```bash
az group show \
  --name $RG \
  --output table
```

---

# 8. 🌐 Step 2 — Create VNet

Create:

```text
myrg-vnet
10.0.0.0/16
```

```bash
az network vnet create \
  --resource-group $RG \
  --name $VNET \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $APP_SUBNET \
  --subnet-prefix 10.0.1.0/24
```

Create client subnet:

```bash
az network vnet subnet create \
  --resource-group $RG \
  --vnet-name $VNET \
  --name $CLIENT_SUBNET \
  --address-prefixes 10.0.2.0/24
```

Verify:

```bash
az network vnet subnet list \
  --resource-group $RG \
  --vnet-name $VNET \
  --output table
```

---

# 9. ⚖️ Step 3 — Create Public IP for Load Balancer

```bash
az network public-ip create \
  --resource-group $RG \
  --name $PIP \
  --sku Standard \
  --allocation-method Static
```

Get the actual IP:

```bash
LB_PUBLIC_IP=$(az network public-ip show \
  --resource-group $RG \
  --name $PIP \
  --query ipAddress \
  --output tsv)

echo $LB_PUBLIC_IP
```

Example:

```text
40.89.249.236
```

Your address will normally be different.

---

# 10. ⚖️ Step 4 — Create Azure Load Balancer

Create the Load Balancer:

```bash
az network lb create \
  --resource-group $RG \
  --name $LB \
  --sku Standard \
  --public-ip-address $PIP \
  --frontend-ip-name LoadBalancerFrontEnd \
  --backend-pool-name $BACKEND_POOL
```

Verify:

```bash
az network lb show \
  --resource-group $RG \
  --name $LB \
  --output table
```

---

# 11. 🩺 Step 5 — Create Health Probe

The Load Balancer must know whether Nginx is healthy.

Create a TCP probe:

```bash
az network lb probe create \
  --resource-group $RG \
  --lb-name $LB \
  --name http-probe \
  --protocol Tcp \
  --port 80
```

For a more application-aware demonstration, you can use an HTTP probe:

```bash
az network lb probe create \
  --resource-group $RG \
  --lb-name $LB \
  --name http-probe \
  --protocol Http \
  --port 80 \
  --path /
```

---

# 12. 🔀 Step 6 — Create Load Balancing Rule

```bash
az network lb rule create \
  --resource-group $RG \
  --lb-name $LB \
  --name http-rule \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name LoadBalancerFrontEnd \
  --backend-pool-name $BACKEND_POOL \
  --probe-name http-probe
```

The flow becomes:

```text
Public IP :80
     |
     v
Load Balancer
     |
     v
web-pool
     |
 +---+---+
 |       |
 v       v
VM1     VM2
:80     :80
```

---

# 13. 💻 Step 7 — Create Backend VM 1

Create the first VM:

```bash
az vm create \
  --resource-group $RG \
  --name $VM1 \
  --image Ubuntu2404 \
  --vnet-name $VNET \
  --subnet $APP_SUBNET \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```

Get its NIC:

```bash
NIC1=$(az vm show \
  --resource-group $RG \
  --name $VM1 \
  --show-details \
  --query networkProfile.networkInterfaces[0].id \
  --output tsv)

NIC1_NAME=$(basename $NIC1)

echo $NIC1_NAME
```

---

# 14. 💻 Step 8 — Create Backend VM 2

```bash
az vm create \
  --resource-group $RG \
  --name $VM2 \
  --image Ubuntu2404 \
  --vnet-name $VNET \
  --subnet $APP_SUBNET \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```

Get its NIC:

```bash
NIC2=$(az vm show \
  --resource-group $RG \
  --name $VM2 \
  --show-details \
  --query networkProfile.networkInterfaces[0].id \
  --output tsv)

NIC2_NAME=$(basename $NIC2)

echo $NIC2_NAME
```

---

# 15. 🧩 Step 9 — Add Both NICs to Backend Pool

Add VM1 NIC:

```bash
az network lb address-pool address add \
  --resource-group $RG \
  --lb-name $LB \
  --pool-name $BACKEND_POOL \
  --vnet $VNET \
  --ip-address <VM1-PRIVATE-IP>
```

Add VM2 NIC:

```bash
az network lb address-pool address add \
  --resource-group $RG \
  --lb-name $LB \
  --pool-name $BACKEND_POOL \
  --vnet $VNET \
  --ip-address <VM2-PRIVATE-IP>
```

Get private IPs:

```bash
az vm list-ip-addresses \
  --resource-group $RG \
  --name $VM1 \
  --output table
```

```bash
az vm list-ip-addresses \
  --resource-group $RG \
  --name $VM2 \
  --output table
```

Use the private IPs shown by Azure.

---

# 16. 🎨 Step 10 — Install Beautiful Nginx Page on VM1

SSH to VM1:

```bash
ssh azureuser@<VM1-PUBLIC-IP>
```

Install Nginx:

```bash
sudo apt update
sudo apt install -y nginx
```

Create the VM1 page:

```bash
sudo tee /var/www/html/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Learning Hub Tech - App Server 01</title>
    <style>
        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            font-family: Arial, Helvetica, sans-serif;
            background: linear-gradient(135deg, #071952, #088395, #35A29F);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }

        .card {
            width: 85%;
            max-width: 850px;
            padding: 55px;
            border-radius: 28px;
            background: rgba(255,255,255,0.12);
            border: 1px solid rgba(255,255,255,0.25);
            box-shadow: 0 25px 60px rgba(0,0,0,0.35);
            text-align: center;
            backdrop-filter: blur(10px);
        }

        .logo {
            font-size: 22px;
            letter-spacing: 5px;
            font-weight: bold;
            margin-bottom: 25px;
        }

        h1 {
            font-size: 52px;
            margin: 10px 0;
        }

        h2 {
            font-size: 28px;
            margin: 15px 0;
        }

        .badge {
            display: inline-block;
            padding: 12px 25px;
            border-radius: 30px;
            background: rgba(255,255,255,0.2);
            font-size: 18px;
            margin-top: 20px;
        }

        .info {
            margin-top: 30px;
            line-height: 1.8;
            font-size: 17px;
        }

        .status {
            margin-top: 30px;
            font-size: 20px;
            font-weight: bold;
        }
    </style>
</head>

<body>
    <div class="card">

        <div class="logo">LEARNING HUB TECH</div>

        <h1>🚀 APP SERVER 01</h1>

        <h2>Backend VM 1</h2>

        <div class="badge">
            NGINX • HEALTHY • ONLINE
        </div>

        <div class="info">
            <p>Request successfully reached <strong>Backend VM 01</strong>.</p>
            <p>This page is being served by Nginx.</p>
            <p>Azure Load Balancer → web-pool → VM01</p>
        </div>

        <div class="status">
            🟢 SERVER 01 IS SERVING TRAFFIC
        </div>

    </div>
</body>
</html>
EOF
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```

Enable Nginx:

```bash
sudo systemctl enable nginx
```

Test:

```bash
curl http://localhost
```

---

# 17. 🎨 Step 11 — Install Different Nginx Page on VM2

SSH to VM2:

```bash
ssh azureuser@<VM2-PUBLIC-IP>
```

Install Nginx:

```bash
sudo apt update
sudo apt install -y nginx
```

Create a DIFFERENT page:

```bash
sudo tee /var/www/html/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Learning Hub Tech - App Server 02</title>
    <style>
        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            font-family: Arial, Helvetica, sans-serif;
            background: linear-gradient(135deg, #3B0764, #7E22CE, #EC4899);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }

        .card {
            width: 85%;
            max-width: 850px;
            padding: 55px;
            border-radius: 28px;
            background: rgba(255,255,255,0.12);
            border: 1px solid rgba(255,255,255,0.25);
            box-shadow: 0 25px 60px rgba(0,0,0,0.35);
            text-align: center;
            backdrop-filter: blur(10px);
        }

        .logo {
            font-size: 22px;
            letter-spacing: 5px;
            font-weight: bold;
            margin-bottom: 25px;
        }

        h1 {
            font-size: 52px;
            margin: 10px 0;
        }

        h2 {
            font-size: 28px;
            margin: 15px 0;
        }

        .badge {
            display: inline-block;
            padding: 12px 25px;
            border-radius: 30px;
            background: rgba(255,255,255,0.2);
            font-size: 18px;
            margin-top: 20px;
        }

        .info {
            margin-top: 30px;
            line-height: 1.8;
            font-size: 17px;
        }

        .status {
            margin-top: 30px;
            font-size: 20px;
            font-weight: bold;
        }
    </style>
</head>

<body>
    <div class="card">

        <div class="logo">LEARNING HUB TECH</div>

        <h1>⚡ APP SERVER 02</h1>

        <h2>Backend VM 2</h2>

        <div class="badge">
            NGINX • HEALTHY • ONLINE
        </div>

        <div class="info">
            <p>Request successfully reached <strong>Backend VM 02</strong>.</p>
            <p>This page is being served by Nginx.</p>
            <p>Azure Load Balancer → web-pool → VM02</p>
        </div>

        <div class="status">
            🟣 SERVER 02 IS SERVING TRAFFIC
        </div>

    </div>
</body>
</html>
EOF
```

Restart:

```bash
sudo systemctl restart nginx
```

Enable:

```bash
sudo systemctl enable nginx
```

Test:

```bash
curl http://localhost
```

---

# 18. 🔎 Step 12 — Verify Both Backend Pages Directly

On VM1:

```bash
curl http://localhost
```

Expected:

```text
APP SERVER 01
Backend VM 1
```

On VM2:

```bash
curl http://localhost
```

Expected:

```text
APP SERVER 02
Backend VM 2
```

This proves that the two VMs have **different web content**.

---

# 19. 🩺 Step 13 — Verify Nginx Health

VM1:

```bash
curl -I http://localhost
```

VM2:

```bash
curl -I http://localhost
```

Expected:

```text
HTTP/1.1 200 OK
```

The Azure Load Balancer health probe can therefore determine whether the backend is healthy.

---

# 20. 🔐 Step 14 — Configure NSG for HTTP

The backend VMs must allow HTTP traffic.

You can create an NSG:

```bash
az network nsg create \
  --resource-group $RG \
  --name app-nsg
```

Allow HTTP:

```bash
az network nsg rule create \
  --resource-group $RG \
  --nsg-name app-nsg \
  --name AllowHTTP \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --source-address-prefixes Internet
```

For a production design, restrict the source appropriately instead of allowing broad Internet access.

---

# 21. 🌐 Step 15 — Create Private DNS Zone

Create:

```text
learninghubtech.com
```

```bash
az network private-dns zone create \
  --resource-group $RG \
  --name learninghubtech.com
```

Verify:

```bash
az network private-dns zone show \
  --resource-group $RG \
  --name learninghubtech.com \
  --output table
```

---

# 22. 🔗 Step 16 — Link Private DNS Zone to VNet

```bash
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name learninghubtech.com \
  --name myrg-vnet-link \
  --virtual-network $VNET \
  --registration-enabled false
```

Verify:

```bash
az network private-dns link vnet list \
  --resource-group $RG \
  --zone-name learninghubtech.com \
  --output table
```

The architecture now contains:

```text
Private DNS Zone
learninghubtech.com
        |
        | VNet Link
        v
myrg-vnet
10.0.0.0/16
```

---

# 23. 📝 Step 17 — Create the DNS A Record

Get the Load Balancer public IP:

```bash
LB_PUBLIC_IP=$(az network public-ip show \
  --resource-group $RG \
  --name $PIP \
  --query ipAddress \
  --output tsv)

echo $LB_PUBLIC_IP
```

Create the `www` record:

```bash
az network private-dns record-set a create \
  --resource-group $RG \
  --zone-name learninghubtech.com \
  --name www
```

Add the Load Balancer IP:

```bash
az network private-dns record-set a add-record \
  --resource-group $RG \
  --zone-name learninghubtech.com \
  --record-set-name www \
  --ipv4-address $LB_PUBLIC_IP
```

Verify:

```bash
az network private-dns record-set a show \
  --resource-group $RG \
  --zone-name learninghubtech.com \
  --name www
```

The DNS mapping is:

```text
www.learninghubtech.com
          |
          v
    <LB-PUBLIC-IP>
```

---

# 24. 💻 Step 18 — Create VMClient

Create a client VM in the same VNet:

```bash
az vm create \
  --resource-group $RG \
  --name $CLIENT \
  --image Ubuntu2404 \
  --vnet-name $VNET \
  --subnet $CLIENT_SUBNET \
  --admin-username azureuser \
  --generate-ssh-keys
```

SSH into it:

```bash
ssh azureuser@<VMCLIENT-PUBLIC-IP>
```

Install DNS utilities:

```bash
sudo apt update
sudo apt install -y dnsutils curl
```

---

# 25. 🔍 Step 19 — Prove Private DNS Resolution

From `vmclient`:

```bash
nslookup www.learninghubtech.com
```

Expected:

```text
Name:
www.learninghubtech.com

Address:
<LB-PUBLIC-IP>
```

Or:

```bash
dig www.learninghubtech.com
```

This proves:

```text
vmclient
   |
   | DNS query
   v
Private DNS Zone
   |
   | A record
   v
Load Balancer Public IP
```

---

# 26. 🌐 Step 20 — Test the Application Through DNS

From `vmclient`:

```bash
curl http://www.learninghubtech.com
```

The response should be either:

```text
APP SERVER 01
```

or:

```text
APP SERVER 02
```

The Load Balancer decides which healthy backend receives the request.

---

# 27. 🔥 Best Demonstration — Watch Load Balancing

Run:

```bash
for i in {1..20}; do
    curl -s http://www.learninghubtech.com | grep -E "APP SERVER|Backend VM"
done
```

Depending on the Load Balancer distribution and connection behavior, responses can come from different backend servers.

For a cleaner visual test, open:

```text
http://www.learninghubtech.com
```

and refresh repeatedly.

You may see:

```text
🚀 APP SERVER 01
```

then:

```text
⚡ APP SERVER 02
```

The important teaching point is not that every refresh must alternate perfectly. Load-balancer distribution depends on the load-balancing algorithm and connection behavior.

---

# 28. 🧪 Step 21 — Prove Failover

This is the most useful classroom demonstration.

First verify both servers:

```text
VM01 → Nginx → HTTP 200
VM02 → Nginx → HTTP 200
```

Now stop Nginx on VM1:

```bash
sudo systemctl stop nginx
```

Check:

```bash
curl http://localhost
```

It should fail on VM1.

The Load Balancer health probe will eventually mark VM1 unhealthy.

Now from `vmclient`:

```bash
curl http://www.learninghubtech.com
```

Traffic should be served by the healthy backend:

```text
APP SERVER 02
```

This demonstrates:

```text
                 Load Balancer
                      |
                Health Probe
                      |
          +-----------+-----------+
          |                       |
       VM01                    VM02
     UNHEALTHY                HEALTHY
          X                       |
                                  |
                                  v
                              Request
```

---

# 29. 🔄 Step 22 — Bring VM1 Back

On VM1:

```bash
sudo systemctl start nginx
```

Check:

```bash
sudo systemctl status nginx
```

Test:

```bash
curl http://localhost
```

The health probe will eventually detect VM1 as healthy again.

---

# 30. 🔬 Important DNS vs Load Balancer Demonstration

Ask the students:

> "Does DNS select VM1 or VM2?"

Answer:

**No.**

DNS returns:

```text
www.learninghubtech.com
        |
        v
Load Balancer IP
```

The Load Balancer then selects the backend:

```text
Load Balancer
      |
      +---- VM1
      |
      +---- VM2
```

So:

```text
DNS
 ↓
IP address

Load Balancer
 ↓
Backend VM
```

These are two different responsibilities.

---

# 31. 🧠 Important Private DNS Teaching Point

The architecture uses:

```text
Private DNS Zone
       |
       v
www.learninghubtech.com
       |
       v
Public Load Balancer IP
```

Therefore, do not teach this as:

> "Private DNS means the destination is private."

Instead teach:

> **Private DNS means the DNS zone is private and its records are intended for private DNS resolution. The record can still contain a public IP if the architecture is designed that way.**

For private application traffic, use a private/internal Load Balancer or Private Endpoint as appropriate.

---

# 32. 📊 Complete Architecture

```text
                         AZURE
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                 myrg-vnet 10.0.0.0/16                    │
│                                                          │
│   ┌──────────────────────────────────────────────────┐   │
│   │                                                  │   │
│   │          PUBLIC LOAD BALANCER                    │   │
│   │                                                  │   │
│   │        Public IP: <LB-PUBLIC-IP>                 │   │
│   │                  │                               │   │
│   │                  │                               │   │
│   │                  ▼                               │   │
│   │              web-pool                            │   │
│   │                  │                               │   │
│   │          ┌───────┴───────┐                       │   │
│   │          │               │                       │   │
│   │          ▼               ▼                       │   │
│   │      ┌────────┐      ┌────────┐                 │   │
│   │      │ VMAPP01│      │ VMAPP02│                 │   │
│   │      │        │      │        │                 │   │
│   │      │ NGINX  │      │ NGINX  │                 │   │
│   │      │        │      │        │                 │   │
│   │      │ APP 01 │      │ APP 02 │                 │   │
│   │      └────────┘      └────────┘                 │   │
│   │                                                  │   │
│   └──────────────────────────────────────────────────┘   │
│                                                          │
│   ┌───────────────┐                                      │
│   │   VMCLIENT    │                                      │
│   │               │                                      │
│   │ DNS Query     │                                      │
│   └───────┬───────┘                                      │
│           │                                              │
└───────────|──────────────────────────────────────────────┘
            │
            │ DNS resolution
            ▼
┌──────────────────────────────────────────────────────────┐
│             PRIVATE DNS ZONE                             │
│                                                          │
│             learninghubtech.com                          │
│                                                          │
│       www.learninghubtech.com                            │
│                  │                                       │
│                  ▼                                       │
│          <LB-PUBLIC-IP>                                  │
└──────────────────────────────────────────────────────────┘
```

---

# 33. 🎓 Classroom Story

Use this story while teaching:

### Student asks:

> "I don't want users to remember the Load Balancer IP."

Create:

```text
www.learninghubtech.com
```

### DNS says:

```text
www.learninghubtech.com
             ↓
       Load Balancer IP
```

### Load Balancer says:

```text
Which backend is healthy?

VM01 → Healthy
VM02 → Healthy
```

It sends the request to a backend.

### VM01 returns:

```text
🚀 APP SERVER 01
```

or VM02 returns:

```text
⚡ APP SERVER 02
```

If VM01 becomes unhealthy:

```text
VM01 → ❌
VM02 → ✅
```

The Load Balancer continues using VM02.

---

# 34. 🔎 Useful Verification Commands

## DNS Zone

```bash
az network private-dns zone list \
  --resource-group $RG \
  --output table
```

## DNS VNet Link

```bash
az network private-dns link vnet list \
  --resource-group $RG \
  --zone-name $DNS_ZONE \
  --output table
```

## DNS Records

```bash
az network private-dns record-set a list \
  --resource-group $RG \
  --zone-name $DNS_ZONE \
  --output table
```

## Load Balancer

```bash
az network lb show \
  --resource-group $RG \
  --name $LB \
  --output table
```

## Backend Pool

```bash
az network lb address-pool show \
  --resource-group $RG \
  --lb-name $LB \
  --name $BACKEND_POOL
```

## Health Probe

```bash
az network lb probe list \
  --resource-group $RG \
  --lb-name $LB \
  --output table
```

## VM Private IPs

```bash
az vm list-ip-addresses \
  --resource-group $RG \
  --name $VM1 \
  --output table
```

```bash
az vm list-ip-addresses \
  --resource-group $RG \
  --name $VM2 \
  --output table
```

---

# 35. 🧹 Cleanup

Delete the complete lab:

```bash
az group delete \
  --name $RG \
  --yes \
  --no-wait
```

---

# 36. ⭐ Final Teaching Summary

Remember the four layers:

```text
1. DNS
   "What IP belongs to this name?"

       ↓

2. Load Balancer
   "Which healthy backend should receive traffic?"

       ↓

3. Backend VM
   "Which application handles the request?"

       ↓

4. Nginx
   "What HTML response should I return?"
```

In this lab:

```text
www.learninghubtech.com
            ↓
     Private DNS Zone
            ↓
    Load Balancer IP
            ↓
       web-pool
        /      \
       /        \
    VM01        VM02
   Nginx       Nginx
    APP01       APP02
```

## 🏆 Golden Rule

```text
DNS = NAME → IP

LOAD BALANCER = IP → HEALTHY BACKEND

NGINX = HTTP REQUEST → WEBPAGE
```

And the most important distinction:

```text
Private DNS
      ≠
Private Endpoint
      ≠
Private IP
```

They solve different networking problems.
