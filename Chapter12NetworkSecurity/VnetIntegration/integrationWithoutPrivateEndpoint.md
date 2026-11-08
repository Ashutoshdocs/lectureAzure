# Azure VNet Integration Demo — App Service → Azure VM
## Proving VNet Integration Does NOT Require a Private Endpoint

---

## 🎯 Objective

This practical demonstrates **Azure App Service VNet Integration** using an **Azure VM as the private destination**.

The purpose is to prove:

> **VNet Integration does NOT require a Private Endpoint.**

We will build:

```text
                    INTERNET
                       |
                       | HTTP
                       v
              +-------------------+
              | Azure App Service |
              | Web App           |
              +---------+---------+
                        |
                        |
                 VNet Integration
                 OUTBOUND ONLY
                        |
                        v
       +-----------------------------------+
       |       Azure VNet 10.20.0.0/16     |
       |                                   |
       |  +-----------------------------+  |
       |  | App Service Integration     |  |
       |  | Subnet                      |  |
       |  | 10.20.1.0/24                |  |
       |  +-------------+---------------+  |
       |                |                  |
       |                | PRIVATE          |
       |                | NETWORK          |
       |                v                  |
       |  +-----------------------------+  |
       |  | VM Subnet                   |  |
       |  | 10.20.2.0/24                |  |
       |  |                             |  |
       |  | Azure VM                    |  |
       |  | 10.20.2.x                   |  |
       |  | Nginx :80                   |  |
       |  +-----------------------------+  |
       |                                   |
       +-----------------------------------+

             ❌ NO PRIVATE ENDPOINT
             ❌ NO PRIVATE DNS ZONE
             ❌ NO DATABASE
             ❌ NO VNET INJECTION
```

---

# 1. What Are We Proving?

There are three separate concepts:

### VNet Integration

```text
App Service
     |
     | VNet Integration
     v
    VNet
     |
     v
Private VM
```

### Private Endpoint

```text
VNet
 |
 v
Private Endpoint
 |
 v
PaaS Service
```

### VNet Injection

```text
PaaS Service
     |
     v
DIRECTLY DEPLOYED
     |
     v
VNet Subnet
```

This lab uses **only VNet Integration**.

---

# 2. Final Architecture

```text
                         USER
                          |
                          | HTTPS
                          v
                  +---------------+
                  | App Service    |
                  | Public URL     |
                  +-------+-------+
                          |
                          |
                   VNet Integration
                          |
                          | OUTBOUND
                          |
                          v
       +------------------------------------------+
       |             VNet 10.20.0.0/16            |
       |                                          |
       |  Integration Subnet                     |
       |  10.20.1.0/24                           |
       |                                          |
       |  +-----------------------------+         |
       |  | App Service VNet Interface  |         |
       |  +-------------+---------------+         |
       |                |                         |
       |                | Private routing         |
       |                v                         |
       |  VM Subnet                                 |
       |  10.20.2.0/24                              |
       |                                             |
       |  +-----------------------------+            |
       |  | Azure VM                   |            |
       |  | Private IP: 10.20.2.x      |            |
       |  | Nginx :80                  |            |
       |  +-----------------------------+            |
       |                                             |
       +---------------------------------------------+

       PRIVATE ENDPOINT: ❌ NOT USED
```

---

# 3. Prerequisites

You need:

- Azure subscription
- Azure CLI
- PowerShell
- Permission to create Azure resources
- App Service Plan that supports VNet Integration

For App Service VNet Integration, the integration subnet must be dedicated to the integration and delegated to `Microsoft.Web/serverFarms`.

---

# 4. Set Variables

Run in PowerShell:

```powershell
$LOCATION="centralindia"
$RG="VNetIntegrationVMTestRG"

$VNET="vnet-integration-demo"

$INTEGRATION_SUBNET="appservice-integration-subnet"
$VM_SUBNET="vm-subnet"

$PLAN="vnet-integration-plan"
$WEBAPP="vnetintegrationvm$(Get-Random -Minimum 10000 -Maximum 99999)"
$VM="private-web-vm"
```

---

# 5. Create Resource Group

```powershell
az group create `
  --name $RG `
  --location $LOCATION
```

Verify:

```powershell
az group show `
  --name $RG `
  -o table
```

---

# 6. Create VNet

```powershell
az network vnet create `
  --resource-group $RG `
  --name $VNET `
  --location $LOCATION `
  --address-prefix 10.20.0.0/16
```

Verify:

```powershell
az network vnet show `
  --resource-group $RG `
  --name $VNET `
  --query addressSpace.addressPrefixes
```

Expected:

```text
10.20.0.0/16
```

---

# 7. Create App Service Integration Subnet

Create a dedicated subnet for App Service VNet Integration:

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $INTEGRATION_SUBNET `
  --address-prefix 10.20.1.0/24 `
  --delegations Microsoft.Web/serverFarms
```

Verify:

```powershell
az network vnet subnet show `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $INTEGRATION_SUBNET `
  --query "{Name:name,Prefix:addressPrefix,Delegation:delegations[0].serviceName}"
```

Expected:

```text
Name        : appservice-integration-subnet
Prefix      : 10.20.1.0/24
Delegation  : Microsoft.Web/serverFarms
```

---

# 8. Create VM Subnet

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $VM_SUBNET `
  --address-prefix 10.20.2.0/24
```

The VNet now looks like:

```text
10.20.0.0/16
│
├── 10.20.1.0/24
│      App Service Integration
│
└── 10.20.2.0/24
       Azure VM
```

---

# 9. Create Azure VM

Create an Ubuntu VM inside the VNet:

```powershell
az vm create `
  --resource-group $RG `
  --name $VM `
  --location $LOCATION `
  --image Ubuntu2404 `
  --vnet-name $VNET `
  --subnet $VM_SUBNET `
  --admin-username azureuser `
  --generate-ssh-keys
```

Get the VM public IP:

```powershell
$VMPUBLICIP=$(az vm show -d `
  --resource-group $RG `
  --name $VM `
  --query publicIps `
  -o tsv)

$VMPUBLICIP
```

Get the VM private IP:

```powershell
$VMPRIVATEIP=$(az vm show -d `
  --resource-group $RG `
  --name $VM `
  --query privateIps `
  -o tsv)

$VMPRIVATEIP
```

Expected example:

```text
10.20.2.4
```

---

# 10. Open HTTP Port on the VM

Create an NSG rule:

```powershell
az vm open-port `
  --resource-group $RG `
  --name $VM `
  --port 80 `
  --priority 100
```

We will use port 80 for a simple HTTP test.

---

# 11. SSH Into the VM

```powershell
ssh azureuser@$VMPUBLICIP
```

Install Nginx:

```bash
sudo apt update
sudo apt install nginx -y
```

Check:

```bash
systemctl status nginx
```

Expected:

```text
active (running)
```

---

# 12. Create a Special Page on the VM

Replace the default Nginx page:

```bash
sudo tee /var/www/html/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>VNet Integration Proof</title>
    <style>
        body {
            font-family: Arial;
            background: #eef6ff;
            text-align: center;
            padding: 60px;
        }

        .box {
            background: white;
            padding: 40px;
            border-radius: 20px;
            max-width: 800px;
            margin: auto;
            box-shadow: 0 5px 20px rgba(0,0,0,0.15);
        }

        h1 {
            color: #0078d4;
        }

        .private {
            font-size: 28px;
            font-weight: bold;
        }
    </style>
</head>

<body>

<div class="box">

<h1>🎯 VNet Integration Successful</h1>

<h2>Azure App Service → VNet → Azure VM</h2>

<p class="private">
This page is being served by an Azure VM using its PRIVATE IP.
</p>

<p>
VM Private Network:
10.20.2.0/24
</p>

<p>
Port: 80
</p>

<p>
Private Endpoint: NOT USED
</p>

<p>
VNet Injection: NOT USED
</p>

<p>
Networking Method: VNet Integration
</p>

</div>

</body>
</html>
EOF
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```

Test locally:

```bash
curl http://localhost
```

You should see:

```text
VNet Integration Successful
```

---

# 13. Test VM Private IP

From inside the VM:

```bash
hostname -I
```

Example:

```text
10.20.2.4
```

Test:

```bash
curl http://10.20.2.4
```

The page should be returned.

---

# 14. Create App Service Plan

Exit the VM:

```bash
exit
```

Create the Linux App Service Plan:

```powershell
az appservice plan create `
  --resource-group $RG `
  --name $PLAN `
  --location $LOCATION `
  --is-linux `
  --sku B1
```

---

# 15. Create Web App

```powershell
az webapp create `
  --resource-group $RG `
  --plan $PLAN `
  --name $WEBAPP `
  --runtime "PYTHON:3.11"
```

Get the public URL:

```powershell
$WEBURL=$(az webapp show `
  --resource-group $RG `
  --name $WEBAPP `
  --query defaultHostName `
  -o tsv)

$WEBURL
```

Example:

```text
vnetintegrationvm12345.azurewebsites.net
```

---

# 16. Enable VNet Integration

This is the key command:

```powershell
az webapp vnet-integration add `
  --resource-group $RG `
  --name $WEBAPP `
  --vnet $VNET `
  --subnet $INTEGRATION_SUBNET
```

Now the App Service can make outbound connections through the VNet.

---

# 17. Verify VNet Integration

```powershell
az webapp vnet-integration list `
  --resource-group $RG `
  --name $WEBAPP `
  -o table
```

You should see:

```text
VNet                     Subnet
-----------------------  ------------------------------
vnet-integration-demo    appservice-integration-subnet
```

---

# 18. Configure App Service to Call the VM

We need a small Flask application.

Create a folder:

```powershell
mkdir vnet-integration-webapp
cd vnet-integration-webapp
```

Create `app.py`:

```python
import os
import requests
from flask import Flask

app = Flask(__name__)

VM_PRIVATE_IP = os.environ["VM_PRIVATE_IP"]

@app.route("/")
def home():

    try:
        response = requests.get(
            f"http://{VM_PRIVATE_IP}",
            timeout=10
        )

        return f"""
        <html>
        <head>
            <title>VNet Integration Proof</title>
            <style>
                body {{
                    font-family: Arial;
                    background: #eef6ff;
                    padding: 50px;
                }}

                .box {{
                    background: white;
                    padding: 40px;
                    border-radius: 20px;
                    max-width: 900px;
                    margin: auto;
                    box-shadow: 0 5px 20px rgba(0,0,0,.15);
                }}

                h1 {{
                    color: #0078d4;
                }}

                .success {{
                    font-size: 28px;
                    font-weight: bold;
                }}

                pre {{
                    background: #f4f4f4;
                    padding: 20px;
                    overflow: auto;
                }}
            </style>
        </head>

        <body>

        <div class="box">

            <h1>🎯 VNet Integration Proof</h1>

            <p class="success">
            App Service successfully reached Azure VM
            using the VM's PRIVATE IP.
            </p>

            <p>
            App Service
            →
            VNet Integration
            →
            Azure VNet
            →
            Azure VM
            </p>

            <h3>VM Private IP</h3>

            <p>
            {VM_PRIVATE_IP}
            </p>

            <h3>Response received from VM</h3>

            <pre>{response.text}</pre>

            <hr>

            <p>
            ❌ Private Endpoint: NOT USED
            </p>

            <p>
            ❌ VNet Injection: NOT USED
            </p>

            <p>
            ✅ VNet Integration: USED
            </p>

        </div>

        </body>
        </html>
        """

    except Exception as e:

        return f"""
        <h1>Connection Failed</h1>

        <p>Could not reach VM through VNet Integration.</p>

        <pre>{str(e)}</pre>
        """, 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

Create `requirements.txt`:

```text
Flask
requests
gunicorn
```

---

# 19. Configure the VM Private IP

Back in PowerShell:

```powershell
az webapp config appsettings set `
  --resource-group $RG `
  --name $WEBAPP `
  --settings VM_PRIVATE_IP=$VMPRIVATEIP
```

Verify:

```powershell
az webapp config appsettings list `
  --resource-group $RG `
  --name $WEBAPP `
  --query "[?name=='VM_PRIVATE_IP']"
```

---

# 20. Configure Startup Command

```powershell
az webapp config set `
  --resource-group $RG `
  --name $WEBAPP `
  --startup-file "gunicorn --bind=0.0.0.0:8000 app:app"
```

---

# 21. Deploy the Web App

Create ZIP:

```powershell
Compress-Archive `
  -Path app.py,requirements.txt `
  -DestinationPath app.zip `
  -Force
```

Deploy:

```powershell
az webapp deploy `
  --resource-group $RG `
  --name $WEBAPP `
  --src-path app.zip `
  --type zip
```

Restart:

```powershell
az webapp restart `
  --resource-group $RG `
  --name $WEBAPP
```

---

# 22. Open the App Service

Get URL:

```powershell
$WEBURL=$(az webapp show `
  --resource-group $RG `
  --name $WEBAPP `
  --query defaultHostName `
  -o tsv)

$WEBURL
```

Open:

```text
https://<WEBAPP>.azurewebsites.net
```

Expected page:

```text
🎯 VNet Integration Proof

App Service successfully reached Azure VM
using the VM's PRIVATE IP.

App Service
    ↓
VNet Integration
    ↓
Azure VNet
    ↓
Azure VM

VM Private IP
10.20.2.4

Private Endpoint: NOT USED
VNet Injection: NOT USED
VNet Integration: USED
```

---

# 23. ⭐ The Actual Proof

The request path is:

```text
Browser
   |
   | HTTPS
   v
App Service
   |
   | VNet Integration
   |
   v
10.20.1.0/24
   |
   | Private VNet routing
   |
   v
10.20.2.4
   |
   v
Azure VM
   |
   | HTTP :80
   v
Nginx
```

The critical destination is:

```text
10.20.2.4
```

This is a **private IP address**.

There is:

```text
❌ No Private Endpoint
❌ No Private DNS Zone
❌ No VNet Injection
```

---

# 24. ⭐ Prove the VM Is Actually Private

Get the VM NIC information:

```powershell
az vm show `
  --resource-group $RG `
  --name $VM `
  --show-details `
  --query "{PrivateIP:privateIps,PublicIP:publicIps}" `
  -o json
```

Example:

```json
{
    "PrivateIP": "10.20.2.4",
    "PublicIP": "20.x.x.x"
}
```

The application uses:

```text
10.20.2.4
```

NOT:

```text
20.x.x.x
```

Therefore the App Service is connecting to the VM's **private IP**.

---

# 25. ⭐ Prove App Service Is Integrated

```powershell
az webapp vnet-integration list `
  --resource-group $RG `
  --name $WEBAPP `
  -o json
```

Look for:

```text
vnet-integration-demo
```

and:

```text
appservice-integration-subnet
```

---

# 26. ⭐ Prove No Private Endpoint Exists

List private endpoints in the resource group:

```powershell
az network private-endpoint list `
  --resource-group $RG `
  -o table
```

Expected:

```text
No private endpoints
```

Or an empty result.

This is a deliberate part of the lab.

We have:

```text
VNet Integration = YES

Private Endpoint = NO
```

---

# 27. ⭐ Prove No VNet Injection Is Being Used

The App Service is NOT deployed into:

```text
10.20.1.0/24
```

The subnet is an **integration subnet** delegated to:

```text
Microsoft.Web/serverFarms
```

Check:

```powershell
az network vnet subnet show `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $INTEGRATION_SUBNET `
  --query "{AddressPrefix:addressPrefix,Delegation:delegations[0].serviceName}" `
  -o json
```

Expected:

```json
{
    "AddressPrefix": "10.20.1.0/24",
    "Delegation": "Microsoft.Web/serverFarms"
}
```

The App Service uses this subnet for **VNet Integration**.

---

# 28. ⭐ The Most Important Test

Change the VM webpage.

SSH into VM:

```powershell
ssh azureuser@$VMPUBLICIP
```

Change the page:

```bash
sudo sed -i 's/VNet Integration Successful/VNET INTEGRATION PROVED - PRIVATE VM CONNECTION/' /var/www/html/index.html
```

Restart:

```bash
sudo systemctl restart nginx
```

Now refresh:

```text
https://<WEBAPP>.azurewebsites.net
```

You should see the changed VM page through the App Service.

This proves:

```text
Browser
   ↓
App Service
   ↓
VNet Integration
   ↓
Private VM IP
   ↓
Nginx
   ↓
HTML response
```

---

# 29. Optional Strong Test — Stop Nginx

SSH into VM:

```bash
sudo systemctl stop nginx
```

Refresh the App Service webpage.

The App Service should now fail to retrieve the VM page.

Start Nginx again:

```bash
sudo systemctl start nginx
```

Refresh the App Service.

The page should return.

This demonstrates that the response is actually coming from the VM.

---

# 30. Public vs Private Test

The VM has two addresses:

```text
Public IP:
20.x.x.x

Private IP:
10.20.2.4
```

The App Service configuration contains:

```text
VM_PRIVATE_IP=10.20.2.4
```

Therefore:

```text
App Service
     |
     | destination = 10.20.2.4
     |
     v
VNet Integration
     |
     v
Azure VM
```

It does NOT use:

```text
App Service
     |
     | destination = 20.x.x.x
     |
     v
Internet
     |
     v
Azure VM
```

---

# 31. ⭐ Final Proof Table

| Test | Expected Result |
|---|---|
| App Service VNet Integration | ✅ Enabled |
| Integration subnet | `10.20.1.0/24` |
| VM private IP | `10.20.2.x` |
| App Service calls VM private IP | ✅ Works |
| Private Endpoint | ❌ Not used |
| Private DNS Zone | ❌ Not required |
| VNet Injection | ❌ Not used |
| VM Nginx response visible in Web App | ✅ Yes |
| VM public IP used by application | ❌ No |

---

# 32. What This Proves

The successful request demonstrates:

```text
App Service
     |
     | VNet Integration
     v
VNet
     |
     | Private routing
     v
Azure VM Private IP
```

Therefore:

> **Azure App Service VNet Integration can access a private IP resource in an Azure VNet without using a Private Endpoint.**

---

# 33. Important Teaching Point

Do NOT teach:

```text
VNet Integration = Private Endpoint
```

They are different.

Teach:

```text
VNet Integration
        |
        | Gives App Service outbound
        | connectivity into VNet
        v
      VNet
        |
        +------> VM private IP
        |
        +------> Private Endpoint
        |
        +------> Other private resources
```

A Private Endpoint is simply **one possible destination mechanism**.

---

# 34. VNet Integration Without Private Endpoint

```text
                 INTERNET
                    |
                    v
             +-------------+
             | App Service |
             +------+------+
                    |
                    |
             VNet Integration
                    |
                    v
             +-------------+
             | Azure VNet  |
             +------+------+
                    |
                    |
              Private IP
                    |
                    v
             +-------------+
             | Azure VM    |
             | 10.20.2.4   |
             +-------------+

        Private Endpoint = ❌
```

---

# 35. VNet Integration With Private Endpoint

This is a different architecture:

```text
App Service
     |
     | VNet Integration
     v
   VNet
     |
     v
Private Endpoint
     |
     v
PaaS Service

Private Endpoint = ✅
```

The first architecture is enough to demonstrate VNet Integration.

---

# 36. VNet Injection

This is different again:

```text
PaaS Service
     |
     | Service-specific
     | VNet Injection
     v
Dedicated VNet subnet
```

The service itself participates in the VNet deployment model.

---

# 37. Final Three-Line Memory Trick

```text
VNet Integration
= App Service gets OUTBOUND access into VNet

Private Endpoint
= PaaS service gets a PRIVATE IP in VNet

VNet Injection
= Supported PaaS service is DEPLOYED into a VNet subnet
```

---

# 38. Cleanup

When finished:

```powershell
az group delete `
  --name $RG `
  --yes `
  --no-wait
```

This removes:

- App Service
- App Service Plan
- Azure VM
- VNet
- Integration subnet
- VM subnet
- NSG
- Public IP
- NIC
- Other resources in the resource group

---

# 39. Microsoft Documentation

Azure App Service VNet Integration:
https://learn.microsoft.com/azure/app-service/overview-vnet-integration

Enable VNet Integration:
https://learn.microsoft.com/azure/app-service/configure-vnet-integration-enable

VNet Integration Routing:
https://learn.microsoft.com/azure/app-service/configure-vnet-integration-routing

App Service networking features:
https://learn.microsoft.com/azure/app-service/networking-features

---

# 🎓 Final Teaching Statement

> **VNet Integration does not require a Private Endpoint. In this lab, Azure App Service uses VNet Integration to send outbound traffic to an Azure VM's private IP address. The VM is reachable through the VNet, while no Private Endpoint or VNet Injection is involved.**
