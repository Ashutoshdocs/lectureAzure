# Azure VNet Integration — End-to-End Demo with Private Connectivity Proof

## 🎯 Objective

This practical demonstrates **Azure App Service VNet Integration** end to end.

We will create:

- Azure VNet
- App Service integration subnet
- Private endpoint subnet
- Azure PostgreSQL Flexible Server
- PostgreSQL Private Endpoint
- Azure App Service Web App
- VNet Integration from App Service to the VNet
- Private DNS Zone
- A simple web application that connects to PostgreSQL
- Database/table/data queried through the App Service

### What we will prove

```text
Internet
   |
   | HTTP request to Web App
   v
Azure App Service
   |
   | VNet Integration
   |
   | PRIVATE OUTBOUND TRAFFIC
   v
VNet
   |
   v
Private Endpoint
   |
   v
PostgreSQL
```

The important concept is:

> **VNet Integration allows an App Service app to make outbound connections into a VNet. It does NOT provide inbound private access to the App Service.**

Microsoft documents VNet Integration as an outbound connectivity feature. Private Endpoint is the feature used for inbound private access to an App Service. citeturn0search0turn0search3

---

# 1. Architecture

```text
                         INTERNET
                            |
                            | HTTP/HTTPS
                            v
                 +-----------------------+
                 |    Azure App Service  |
                 |    Web App             |
                 |                        |
                 |    Public URL          |
                 +-----------+-----------+
                             |
                             |
                     VNet Integration
                     OUTBOUND ONLY
                             |
                             v
       +------------------------------------------------+
       |              VNet 10.10.0.0/16                 |
       |                                                |
       |  +---------------------+                       |
       |  | App Integration     |                       |
       |  | Subnet              |                       |
       |  | 10.10.1.0/24        |                       |
       |  |                     |                       |
       |  | Microsoft.Web/      |                       |
       |  | serverFarms         |                       |
       |  +----------+----------+                       |
       |             |                                  |
       |             | PRIVATE TRAFFIC                 |
       |             v                                  |
       |  +---------------------+                       |
       |  | Private Endpoint    |                       |
       |  | Subnet              |                       |
       |  | 10.10.2.0/24        |                       |
       |  |                     |                       |
       |  | PostgreSQL PE       |                       |
       |  | 10.10.2.x           |                       |
       |  +----------+----------+                       |
       |             |                                  |
       +-------------|----------------------------------+
                     |
                     v
             PostgreSQL Flexible
                  Server
```

---

# 2. VNet Integration vs VNet Injection

This demo is specifically **VNet Integration**, not VNet Injection.

## VNet Injection

```text
Azure service
      |
      v
DEPLOYED INTO VNET SUBNET
```

Example:

```text
PostgreSQL Flexible Server
        |
        v
PostgreSQL delegated subnet
```

## VNet Integration

```text
Azure App Service
        |
        | outbound connection
        v
Integrated VNet subnet
        |
        v
Private resource
```

The App Service itself is **not deployed into the VNet subnet**.

Microsoft describes App Service VNet Integration as mounting virtual interfaces to App Service workers so outbound calls can access resources in or through the VNet. citeturn0search0

---

# 3. Prerequisites

You need:

- Azure subscription
- Azure CLI
- PowerShell
- An App Service plan that supports VNet Integration
- Permission to create networking resources

VNet Integration requires a dedicated subnet. Microsoft currently documents `/28` as the minimum and `/26` as the recommended minimum for growth. The integration subnet must be empty and delegated to `Microsoft.Web/serverFarms`. citeturn0search1

---

# 4. Set Variables

Run in PowerShell:

```powershell
$LOCATION="centralindia"
$RG="VNetIntegrationDemoRG"

$VNET="vnet-integration-demo"

$INTEGRATION_SUBNET="appservice-integration-subnet"
$PE_SUBNET="private-endpoint-subnet"

$PLAN="web-linux-plan"
$WEBAPP="vnetintegrationweb$(Get-Random -Minimum 10000 -Maximum 99999)"

$PG="pgintegration$(Get-Random -Minimum 10000 -Maximum 99999)"

$PGADMIN="pgadmin"
$PGPASSWORD="P@ssw0rd123456!"
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
  --address-prefix 10.10.0.0/16
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
10.10.0.0/16
```

---

# 7. Create App Service Integration Subnet

Create a dedicated subnet:

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $INTEGRATION_SUBNET `
  --address-prefix 10.10.1.0/24 `
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
Prefix      : 10.10.1.0/24
Delegation  : Microsoft.Web/serverFarms
```

---

# 8. Create Private Endpoint Subnet

This is a different subnet.

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $PE_SUBNET `
  --address-prefix 10.10.2.0/24
```

Important:

```text
Integration subnet
10.10.1.0/24
        |
        | App Service VNet Integration
        |
        X

Private Endpoint subnet
10.10.2.0/24
        |
        | PostgreSQL Private Endpoint
        |
        v
PostgreSQL
```

Do not use the same subnet for VNet Integration and the Private Endpoint. Microsoft documents that the VNet Integration subnet can't be the same subnet as a private endpoint. citeturn0search3

---

# 9. Create PostgreSQL Flexible Server

For this VNet Integration demo, PostgreSQL will be the backend database.

```powershell
az postgres flexible-server create `
  --resource-group $RG `
  --name $PG `
  --location $LOCATION `
  --admin-user $PGADMIN `
  --admin-password $PGPASSWORD `
  --sku-name Standard_B1ms `
  --tier Burstable `
  --storage-size 32 `
  --version 16
```

Get its FQDN:

```powershell
az postgres flexible-server show `
  --resource-group $RG `
  --name $PG `
  --query fullyQualifiedDomainName `
  -o tsv
```

---

# 10. Create PostgreSQL Private Endpoint

Get the PostgreSQL resource ID:

```powershell
$PGID=$(az postgres flexible-server show `
  --resource-group $RG `
  --name $PG `
  --query id `
  -o tsv)
```

Create Private Endpoint:

```powershell
az network private-endpoint create `
  --resource-group $RG `
  --name postgres-private-endpoint `
  --vnet-name $VNET `
  --subnet $PE_SUBNET `
  --private-connection-resource-id $PGID `
  --group-id postgres `
  --connection-name postgres-private-connection
```

This creates a private IP inside:

```text
10.10.2.0/24
```

---

# 11. Create Private DNS Zone

Create the PostgreSQL Private DNS zone:

```powershell
az network private-dns zone create `
  --resource-group $RG `
  --name "private.postgres.database.azure.com"
```

Link it to the VNet:

```powershell
az network private-dns link vnet create `
  --resource-group $RG `
  --zone-name "private.postgres.database.azure.com" `
  --name postgres-dns-link `
  --virtual-network $VNET `
  --registration-enabled false
```

Create DNS zone group for the private endpoint:

```powershell
az network private-endpoint dns-zone-group create `
  --resource-group $RG `
  --endpoint-name postgres-private-endpoint `
  --name postgres-dns-zone-group `
  --private-dns-zone "private.postgres.database.azure.com" `
  --zone-name postgres
```

This is important because the App Service uses the VNet's DNS configuration when integrated with the VNet. Azure documents that, with Azure DNS/private zones linked to the VNet, integrated App Service apps can resolve private endpoints through those zones. citeturn0search0

---

# 12. Get Private Endpoint IP

```powershell
az network private-endpoint show `
  --resource-group $RG `
  --name postgres-private-endpoint `
  --query customDnsConfigs `
  -o json
```

You should see a private IP similar to:

```text
10.10.2.4
```

Your actual IP may be different.

Save it:

```powershell
$PEIP=$(az network private-endpoint show `
  --resource-group $RG `
  --name postgres-private-endpoint `
  --query "customDnsConfigs[0].ipAddresses[0]" `
  -o tsv)
```

Display it:

```powershell
$PEIP
```

---

# 13. Create App Service Plan

Create a Linux App Service plan:

```powershell
az appservice plan create `
  --resource-group $RG `
  --name $PLAN `
  --location $LOCATION `
  --is-linux `
  --sku B1
```

---

# 14. Create Web App

```powershell
az webapp create `
  --resource-group $RG `
  --plan $PLAN `
  --name $WEBAPP `
  --runtime "PYTHON:3.11"
```

Get the URL:

```powershell
az webapp show `
  --resource-group $RG `
  --name $WEBAPP `
  --query defaultHostName `
  -o tsv
```

Example:

```text
vnetintegrationweb12345.azurewebsites.net
```

---

# 15. Enable VNet Integration

Run:

```powershell
az webapp vnet-integration add `
  --resource-group $RG `
  --name $WEBAPP `
  --vnet $VNET `
  --subnet $INTEGRATION_SUBNET
```

Microsoft documents this Azure CLI operation using `az webapp vnet-integration add`. citeturn0search1

---

# 16. Verify VNet Integration

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

# 17. Enable Application Traffic Routing

For a clear demo of application traffic through the VNet:

```powershell
az resource update `
  --resource-group $RG `
  --name $WEBAPP `
  --resource-type "Microsoft.Web/sites" `
  --set properties.outboundVnetRouting.applicationTraffic=true
```

For routing all outbound application/configuration traffic through the VNet:

```powershell
az resource update `
  --resource-group $RG `
  --name $WEBAPP `
  --resource-type "Microsoft.Web/sites" `
  --set properties.outboundVnetRouting.allTraffic=true
```

Current App Service networking uses `outboundVnetRouting.applicationTraffic` and `outboundVnetRouting.allTraffic`; the older `WEBSITE_VNET_ROUTE_ALL`/`vnetRouteAllEnabled` settings remain supported for compatibility. citeturn0search2

---

# 18. Create PostgreSQL Database

Connect from an environment that can reach the PostgreSQL server.

For example, from an Azure VM in the VNet:

```bash
psql "host=<POSTGRES-FQDN> port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Create the database:

```sql
CREATE DATABASE vnetintegrationdb;
```

Connect:

```sql
\c vnetintegrationdb
```

Create table:

```sql
CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    course VARCHAR(100),
    city VARCHAR(100)
);
```

Insert data:

```sql
INSERT INTO students (name, course, city)
VALUES
('Rahul', 'Azure Networking', 'Pune'),
('Priya', 'Kubernetes', 'Mumbai'),
('Amit', 'Terraform', 'Delhi'),
('Neha', 'Azure DevOps', 'Bangalore');
```

Verify:

```sql
SELECT * FROM students;
```

Expected:

```text
 id | name  |       course        |   city
----+-------+---------------------+-----------
  1 | Rahul | Azure Networking    | Pune
  2 | Priya | Kubernetes          | Mumbai
  3 | Amit  | Terraform           | Delhi
  4 | Neha  | Azure DevOps        | Bangalore
```

---

# 19. Create a Web App That Queries PostgreSQL

Create a local folder:

```powershell
mkdir vnet-integration-demo
cd vnet-integration-demo
```

Create `app.py`:

```python
import os
import psycopg2
from flask import Flask

app = Flask(__name__)

DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

@app.route("/")
def home():
    conn = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        sslmode="require"
    )

    cur = conn.cursor()

    cur.execute("""
        SELECT id, name, course, city
        FROM students
        ORDER BY id
    """)

    rows = cur.fetchall()

    cur.close()
    conn.close()

    html = """
    <html>
    <head>
      <title>VNet Integration Demo</title>
      <style>
        body {
          font-family: Arial;
          background: #eef6ff;
          padding: 40px;
        }
        .box {
          background: white;
          padding: 30px;
          border-radius: 15px;
          max-width: 900px;
          margin: auto;
          box-shadow: 0 4px 15px rgba(0,0,0,.15);
        }
        table {
          width: 100%;
          border-collapse: collapse;
        }
        th, td {
          padding: 12px;
          border: 1px solid #ddd;
        }
        th {
          background: #0078d4;
          color: white;
        }
      </style>
    </head>
    <body>
      <div class="box">
        <h1>Azure VNet Integration Demo</h1>
        <p>App Service → VNet Integration → PostgreSQL Private Endpoint</p>
        <table>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Course</th>
            <th>City</th>
          </tr>
    """

    for row in rows:
        html += f"""
          <tr>
            <td>{row[0]}</td>
            <td>{row[1]}</td>
            <td>{row[2]}</td>
            <td>{row[3]}</td>
          </tr>
        """

    html += """
        </table>
      </div>
    </body>
    </html>
    """

    return html

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

Create `requirements.txt`:

```text
Flask
psycopg2-binary
gunicorn
```

---

# 20. Configure PostgreSQL Connection Settings

Set App Service application settings:

```powershell
$PGFQDN=$(az postgres flexible-server show `
  --resource-group $RG `
  --name $PG `
  --query fullyQualifiedDomainName `
  -o tsv)
```

```powershell
az webapp config appsettings set `
  --resource-group $RG `
  --name $WEBAPP `
  --settings `
  DB_HOST=$PGFQDN `
  DB_NAME=vnetintegrationdb `
  DB_USER=$PGADMIN `
  DB_PASSWORD=$PGPASSWORD
```

Set startup command:

```powershell
az webapp config set `
  --resource-group $RG `
  --name $WEBAPP `
  --startup-file "gunicorn --bind=0.0.0.0:8000 app:app"
```

---

# 21. Deploy the Application

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

# 22. Open the Application

Get URL:

```powershell
$URL=$(az webapp show `
  --resource-group $RG `
  --name $WEBAPP `
  --query defaultHostName `
  -o tsv)

$URL
```

Open:

```text
https://<WEBAPP>.azurewebsites.net
```

Expected:

```text
Azure VNet Integration Demo

App Service → VNet Integration → PostgreSQL Private Endpoint

ID   Name    Course              City
1    Rahul   Azure Networking    Pune
2    Priya   Kubernetes          Mumbai
3    Amit    Terraform           Delhi
4    Neha    Azure DevOps        Bangalore
```

The webpage proves the application successfully queried PostgreSQL.

---

# 23. ⭐ PROOF #1 — Private Endpoint Has a Private IP

Run:

```powershell
az network private-endpoint show `
  --resource-group $RG `
  --name postgres-private-endpoint `
  --query customDnsConfigs `
  -o json
```

Example:

```text
10.10.2.4
```

This IP belongs to:

```text
VNet 10.10.0.0/16
Private Endpoint subnet 10.10.2.0/24
```

Therefore:

```text
PostgreSQL Private Endpoint
          |
          v
      10.10.2.4
```

---

# 24. ⭐ PROOF #2 — DNS Resolves to Private IP

The App Service must resolve the PostgreSQL hostname to the private endpoint.

The private DNS zone:

```text
private.postgres.database.azure.com
```

is linked to:

```text
vnet-integration-demo
```

Check:

```powershell
az network private-dns link vnet list `
  --resource-group $RG `
  --zone-name "private.postgres.database.azure.com" `
  -o table
```

Check the A record:

```powershell
az network private-dns record-set a list `
  --resource-group $RG `
  --zone-name "private.postgres.database.azure.com" `
  -o table
```

The PostgreSQL hostname should resolve through the private DNS configuration to the Private Endpoint IP.

---

# 25. ⭐ PROOF #3 — App Service Uses VNet Integration

```powershell
az webapp vnet-integration list `
  --resource-group $RG `
  --name $WEBAPP `
  -o json
```

You should see the VNet/subnet used by the application.

The architecture is:

```text
App Service
     |
     | VNet Integration
     v
10.10.1.0/24
     |
     | private routing
     v
10.10.2.0/24
     |
     v
Private Endpoint
     |
     v
PostgreSQL
```

---

# 26. ⭐ PROOF #4 — The Application Reads Real Database Data

Open:

```text
https://<WEBAPP>.azurewebsites.net
```

If the browser displays:

```text
Rahul
Priya
Amit
Neha
```

those rows came from PostgreSQL.

The application executes:

```sql
SELECT id, name, course, city
FROM students
ORDER BY id;
```

The data is therefore:

```text
PostgreSQL
     |
     | SQL query
     v
App Service
     |
     | HTTP response
     v
Browser
```

---

# 27. ⭐ PROOF #5 — Change Database Data

Connect to PostgreSQL and execute:

```sql
INSERT INTO students (name, course, city)
VALUES ('Kiran', 'Azure VNet Integration', 'Hyderabad');
```

Then:

```sql
SELECT * FROM students;
```

Refresh the browser.

You should now see:

```text
Kiran
Azure VNet Integration
Hyderabad
```

This is a powerful end-to-end demonstration:

```text
PostgreSQL
   |
   | Database changed
   v
Private Endpoint
   |
   | Private network
   v
VNet Integration
   |
   v
App Service
   |
   | HTTP
   v
Browser
```

---

# 28. ⭐ PROOF #6 — Compare With a Public PostgreSQL Path

The important distinction is:

```text
PUBLIC DATABASE PATH

App Service
     |
     | Internet/public endpoint
     v
PostgreSQL public endpoint
```

versus:

```text
THIS DEMO

App Service
     |
     | VNet Integration
     v
VNet
     |
     | Private IP
     v
Private Endpoint
     |
     v
PostgreSQL
```

The Private Endpoint provides a private IP in your VNet. The App Service VNet Integration provides the outbound path into the VNet. Microsoft specifically documents that VNet Integration can reach private-endpoint-enabled services. citeturn0search0

---

# 29. ⭐ Very Important: VNet Integration Does NOT Make the Web App Private

This is the most common student mistake.

If you open:

```text
https://<WEBAPP>.azurewebsites.net
```

from your laptop, the request can still reach the public App Service endpoint.

That is because:

```text
VNet Integration
=
OUTBOUND from App Service
```

It does NOT mean:

```text
VNet Integration
=
INBOUND private access to App Service
```

For inbound private access to an App Service, use:

```text
Private Endpoint
```

Microsoft explicitly distinguishes these two features. citeturn0search0turn0search3

---

# 30. Final Architecture to Teach

```text
                         INTERNET
                            |
                            | HTTP
                            v
                  +-------------------+
                  |   APP SERVICE     |
                  |   Public URL      |
                  +---------+---------+
                            |
                            |
                    VNET INTEGRATION
                    OUTBOUND ONLY
                            |
                            v
       +----------------------------------------+
       |             AZURE VNET                 |
       |             10.10.0.0/16               |
       |                                        |
       |  +-------------------------------+     |
       |  | Integration Subnet            |     |
       |  | 10.10.1.0/24                 |     |
       |  | Microsoft.Web/serverFarms     |     |
       |  +---------------+---------------+     |
       |                  |                     |
       |                  | PRIVATE             |
       |                  v                     |
       |  +-------------------------------+     |
       |  | Private Endpoint Subnet       |     |
       |  | 10.10.2.0/24                 |     |
       |  |                               |     |
       |  | PostgreSQL Private Endpoint   |     |
       |  | 10.10.2.x                     |     |
       |  +---------------+---------------+     |
       |                  |                     |
       +------------------|---------------------+
                          |
                          v
                PostgreSQL Flexible
                     Server
                          |
                          v
                    vnetintegrationdb
                          |
                          v
                       students
```

---

# 31. VNet Integration vs VNet Injection — Final Comparison

| Feature | VNet Injection | VNet Integration |
|---|---|---|
| Service | Service-specific | App Service / Functions / Logic Apps |
| Service deployed into your subnet? | Yes, for supported services | No |
| Dedicated subnet | Service-specific | Yes |
| Example | PostgreSQL Flexible Server private access | App Service |
| Direction | Depends on service | Outbound |
| Private Endpoint required? | Not necessarily | Useful/required when destination is a PaaS service exposed privately |
| App Service itself placed in VNet? | No | No |
| Private resource access | Service-specific | Yes |
| Inbound access to App Service | No | No |
| Inbound private App Service access | Use Private Endpoint | Use Private Endpoint |

Microsoft's current App Service guidance describes VNet Integration as outbound connectivity and recommends combining it with Private Endpoints when the application needs private access to PaaS services. citeturn0search5turn0search6

---

# 32. One-Line Teaching Definition

> **VNet Integration = an Azure App Service gets an outbound private network path into a VNet so it can access private resources such as VMs, private endpoints, and services secured with networking controls.**

---

# 33. Cleanup

When the practical is finished:

```powershell
az group delete `
  --name $RG `
  --yes `
  --no-wait
```

This removes:

- App Service
- App Service Plan
- VNet
- Integration subnet
- Private Endpoint
- Private DNS Zone
- PostgreSQL server
- Associated resources

---

# 34. Microsoft References

- Azure App Service VNet Integration:
  https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration

- Enable VNet Integration:
  https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-enable

- VNet Integration Routing:
  https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-routing

- App Service Private Endpoint:
  https://learn.microsoft.com/en-us/azure/app-service/networking/private-endpoint
