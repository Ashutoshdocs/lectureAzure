# Azure App Service VNet Integration — Without VNet Injection

> **Objective:** Build and prove Azure App Service **regional VNet Integration** for outbound connectivity to a private Azure SQL Database. The Web App Service remains a multi-tenant App Service; it is **not deployed/injected into the VNet**.
>
> **Important:** This demo uses **App Service VNet Integration + Azure SQL private endpoint**. It does **not** use VNet injection for App Service, and it does not use PostgreSQL Flexible Server deployed into a delegated database subnet. The Private Endpoint is for Azure SQL Database, not for the Web App Service.

This is a production-style learning lab, not a claim that the resources have already been deployed. Capture evidence from your actual Azure subscription.

---

## 1. Learning objectives

By the end, you should be able to:

1. Explain why App Service VNet Integration is not the same as VNet injection.
2. Create a VNet with a dedicated subnet delegated to `Microsoft.Web/serverFarms`.
3. Configure regional VNet Integration on a Linux Azure Web App Service.
4. Create an Azure SQL logical server and database with private endpoint connectivity.
5. Configure private DNS so the SQL FQDN resolves to a private IP.
6. Prove that the Web App Service can query SQL over private network connectivity.
7. Show that the Web App Service itself is not deployed inside the VNet.
8. Collect screenshots and troubleshooting evidence suitable for a teaching practical.

## 2. Concepts: integration vs injection

| Concept | What it means | In this lab |
|---|---|---|
| **App Service VNet Integration** | Routes supported outbound traffic from App Service into a VNet through a dedicated integration subnet | **Yes** |
| **VNet injection** | A supported service is deployed into a customer-managed VNet/subnet as part of its network placement model | **No** |
| **Private Endpoint** | Adds a private IP network interface in a VNet for private access to a supported service | **Yes, for Azure SQL Database** |
| **App Service Private Endpoint** | Provides private inbound access to the Web App Service | **No** |

**Core teaching point:** VNet Integration lets the Web App Service initiate outbound connections to resources reachable through the VNet. It does not put the Web App Service worker into your VNet, and it does not automatically make inbound web access private.

---

## 3. Architecture

```text
                    User / Browser
                          |
                          | HTTPS
                          v
             +---------------------------+
             | Azure Web App Service     |
             | web-vnet-outbound-demo    |
             | Linux / Flask             |
             | NOT injected into VNet    |
             +-------------+-------------+
                           |
                           | Outbound VNet Integration
                           v
+---------------------------------------------------------------------+
| Azure VNet: vnet-app-integration                                    |
| Address space: 10.50.0.0/16                                         |
|                                                                     |
|  +--------------------------------+                                 |
|  | snet-appservice-integration    |                                 |
|  | 10.50.1.0/26 (example)         |                                 |
|  | Delegation: Microsoft.Web/     |                                 |
|  | serverFarms                    |                                 |
|  +--------------------------------+                                 |
|                                                                     |
|  +--------------------------------+                                 |
|  | snet-private-endpoints         |                                 |
|  | 10.50.2.0/24 (example)         |                                 |
|  | Azure SQL Private Endpoint NIC |                                 |
|  +----------------+---------------+                                 |
|                   |                                                 |
|                   | Private DNS: privatelink.database.windows.net  |
+-------------------|-------------------------------------------------+
                    |
                    v
          +----------------------------+
          | Azure SQL Database         |
          | SQL logical server         |
          | Public access disabled     |
          | Private endpoint access    |
          +----------------------------+
```

### Request flow

1. The browser accesses the Web App Service's HTTPS URL.
2. The Web App Service code receives a request to `/health/db`.
3. The code connects to the SQL logical server's normal FQDN, such as `myserver.database.windows.net`, on TCP port `1433`.
4. App Service VNet Integration routes supported outbound traffic through the integration subnet into `vnet-app-integration`.
5. Private DNS resolves the SQL FQDN through the Private Link DNS configuration to the private endpoint address.
6. The Azure SQL Private Endpoint carries the connection to the SQL Database.
7. The query result returns to the Web App Service and is displayed in the health response.

The Web App Service is still an App Service resource outside the VNet's address space. The **outbound path** is integrated; the service is not VNet-injected.

---

## 4. Resource plan

Example region: **Central India**. Verify regional support, quota and SKU availability before creating resources.

| Resource | Name | Example |
|---|---|---|
| Resource group | `rg-app-vnet-integration` | Central India |
| VNet | `vnet-app-integration` | `10.50.0.0/16` |
| Integration subnet | `snet-appservice-integration` | `10.50.1.0/26`, delegated |
| Private Endpoint subnet | `snet-private-endpoints` | `10.50.2.0/24` |
| Private DNS zone | `privatelink.database.windows.net` | Linked to VNet |
| SQL logical server | `sql-vnet-demo-<unique>` | Public network access disabled after PE setup |
| SQL database | `sqldb-vnet-demo` | Small demo database |
| App Service plan | `asp-vnet-outbound-demo` | SKU supporting VNet Integration |
| Web App Service | `web-vnet-outbound-<unique>` | Linux / Python |
| Application | Flask DB health endpoint | Query SQL over private connectivity |

Use a globally unique Web App Service and SQL server name. The example CIDRs must not overlap with existing VNets, VPN networks, or on-premises ranges.

### Prerequisites

- Azure subscription and permissions to create App Service, SQL, networking, Private Endpoint and DNS resources.
- App Service plan/SKU that supports regional VNet Integration.
- An Azure SQL configuration that supports Private Link.
- A secure approach for database credentials; do not commit secrets to source control.
- Budget awareness: App Service plan, SQL Database and network resources can incur charges.

---

## 5. Create the resource group and VNet

### 5.1 Create resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Select the subscription.
4. Name: `rg-app-vnet-integration`.
5. Region: Central India.
6. Select **Review + create** → **Create**.

### 5.2 Create the VNet

1. Search **Virtual networks** → **Create**.
2. Resource group: `rg-app-vnet-integration`.
3. Name: `vnet-app-integration`.
4. Region: Central India.
5. Address space: `10.50.0.0/16`.
6. Create:
   - `snet-appservice-integration`: `10.50.1.0/26` (example; verify the current App Service integration subnet sizing requirements for your plan and scale).
   - `snet-private-endpoints`: `10.50.2.0/24`.
7. Create the VNet.

### 5.3 Delegate the integration subnet

1. Open `vnet-app-integration` → **Subnets**.
2. Select `snet-appservice-integration`.
3. Set **Subnet delegation** to `Microsoft.Web/serverFarms`.
4. Save.

This subnet must be dedicated to App Service VNet Integration. Do not place VMs or Private Endpoint NICs in it.

Keep `snet-private-endpoints` separate. A Private Endpoint subnet generally should not be delegated to `Microsoft.Web/serverFarms`.

---

## 6. Create Azure SQL Database

1. Search **SQL databases** → **Create**.
2. Select or create the SQL logical server.
3. Use resource group `rg-app-vnet-integration`.
4. Database name: `sqldb-vnet-demo`.
5. Choose a lab-appropriate compute/service tier.
6. Configure an administrator and authentication according to your security policy.
7. Complete deployment.

For a private-only target, configure the Private Endpoint and verify connectivity before disabling public access if your workflow requires it. Then disable public network access and verify the app still works through the private path.

### Create a teaching table

Connect to the database using an approved administration path, such as Azure Data Studio/SQL Server Management Studio from an authorized workstation with permitted access, or a controlled admin environment.

Run:

```sql
CREATE TABLE dbo.DemoStatus (
    Id int NOT NULL PRIMARY KEY,
    Message nvarchar(200) NOT NULL
);

IF EXISTS (SELECT 1 FROM dbo.DemoStatus WHERE Id = 1)
    UPDATE dbo.DemoStatus
       SET Message = N'Azure SQL reached over App Service VNet Integration'
     WHERE Id = 1;
ELSE
    INSERT INTO dbo.DemoStatus (Id, Message)
    VALUES (1, N'Azure SQL reached over App Service VNet Integration');

SELECT * FROM dbo.DemoStatus;
```

Use a least-privilege SQL user for the application. Prefer Microsoft Entra authentication or a managed identity-based approach where supported by your selected driver and application design. The sample below uses SQL credentials for straightforward teaching; protect them as secrets.

---

## 7. Create an Azure SQL Private Endpoint

1. Search **Private endpoints** → **Create**.
2. Resource group: `rg-app-vnet-integration`.
3. Name: `pe-sql-vnet-demo`.
4. Region: Central India.
5. Resource:
   - Connect to an Azure resource in your directory.
   - Resource type: `Microsoft.Sql/servers`.
   - Select the SQL logical server created above.
   - Target sub-resource: `sqlServer`.
6. Virtual network:
   - VNet: `vnet-app-integration`.
   - Subnet: `snet-private-endpoints`.
7. DNS:
   - Integrate with private DNS.
   - Select/create `privatelink.database.windows.net`.
   - Ensure the zone is linked to `vnet-app-integration`.
8. Review + create → Create.
9. Open the Private Endpoint and verify provisioning state is **Succeeded** and connection state is **Approved**.

### DNS check

The application should connect using the normal SQL FQDN:

```text
sql-vnet-demo-<unique>.database.windows.net
```

Private DNS provides the private resolution path for the endpoint. Do not hard-code the endpoint IP into the application connection string. Verify the record and VNet link in the portal.

---

## 8. Create the Azure Web App Service

1. Search **App Services** → **Create** → **Web App**.
2. Basics:
   - Resource group: `rg-app-vnet-integration`
   - Name: `web-vnet-outbound-<unique>`
   - Publish: Code
   - Runtime: a supported Python version
   - OS: Linux
   - Region: Central India
3. Create App Service plan `asp-vnet-outbound-demo`.
4. Select a plan/SKU that supports regional VNet Integration. Do not assume Free or Shared plans support it.
5. Review + create → Create.

### Configure VNet Integration

1. Open the Web App Service.
2. Navigate to **Networking** → **VNet Integration** (the portal location may vary).
3. Select **Add VNet** / **Configure VNet Integration**.
4. Choose `vnet-app-integration`.
5. Select `snet-appservice-integration`.
6. Save and wait until the integration is connected.

**Do not select `snet-private-endpoints`.** App Service Integration requires its own delegated subnet.

### Configure application settings

Open the Web App Service's **Settings → Environment variables** (or **Configuration** in some portal experiences) and add:

- `SQL_SERVER`: SQL logical server FQDN, e.g. `sql-vnet-demo-<unique>.database.windows.net`
- `SQL_DATABASE`: `sqldb-vnet-demo`
- `SQL_USER`: least-privilege SQL user
- `SQL_PASSWORD`: store as an approved secret or Key Vault reference; do not commit it to Git
- `SQL_DRIVER`: `ODBC Driver 18 for SQL Server` (if using the sample below)
- `SCM_DO_BUILD_DURING_DEPLOYMENT` : `true`

Save and restart if the portal asks you to.

---

## 9. Deploy a Flask connectivity demo

The endpoint will query `dbo.DemoStatus` and return the result. It is a teaching example, not a complete production application.

### `requirements.txt`

```text
Flask
gunicorn
pyodbc
```

**ODBC prerequisite:** `pyodbc` needs Microsoft ODBC Driver 18 for SQL Server installed in the runtime. For Azure App Service, use a supported custom container or a deployment/runtime setup that explicitly includes the driver. A plain Python runtime may not include it. If you use a custom container, install the driver using Microsoft's current Linux instructions and set the App Service container configuration accordingly.

### `app.py`

```python
import os
import logging
from flask import Flask, jsonify
import pyodbc

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

def get_connection():
    required = ["SQL_SERVER", "SQL_DATABASE", "SQL_USER", "SQL_PASSWORD"]
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError("Missing required SQL application settings: " + ", ".join(missing))

    driver = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER=tcp:{os.environ['SQL_SERVER']},1433;"
        f"DATABASE={os.environ['SQL_DATABASE']};"
        f"UID={os.environ['SQL_USER']};"
        f"PWD={os.environ['SQL_PASSWORD']};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=8;"
    )
    return pyodbc.connect(connection_string)

@app.get("/")
def home():
    return """
    <h1>Azure App Service VNet Integration Demo</h1>
    <p>This Web App Service is not VNet-injected.</p>
    <p>Try <a href="/health/db">/health/db</a> to test Azure SQL private connectivity.</p>
    """

@app.get("/health/db")
def database_health():
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT Message FROM dbo.DemoStatus WHERE Id = ?", 1)
            row = cursor.fetchone()

        if row:
            return jsonify(
                status="connected",
                message=row[0],
                path="App Service -> VNet Integration -> Azure SQL Private Endpoint"
            ), 200

        return jsonify(status="connected", message="SQL connection succeeded; demo row not found"), 200

    except Exception:
        # Keep connection details and credentials out of public responses.
        app.logger.exception("Azure SQL health query failed")
        return jsonify(status="error", message="Database check failed; inspect application logs"), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
```

### Startup command

Configure the startup command for the selected App Service runtime:

```bash
gunicorn --bind 0.0.0.0:8000 app:app
```

The deployed application root must contain `app.py` and `requirements.txt`. For a standard Python App Service, confirm the supported startup and dependency behavior. Because `pyodbc` requires a native ODBC driver, a custom container with the driver installed is the most predictable teaching approach.

### Deploy

Use Deployment Center, a CI/CD pipeline, or a supported ZIP deployment. Example CLI for a prepared `app.zip`:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az webapp deploy  --resource-group rg-app-vnet-integration    --name web-vnet-outbound    --src-path app.zip    --type zip --track-status false
```

Create the archive so `app.py` and `requirements.txt` are at its root. For custom containers, deploy the image and configure the container settings instead.

---

## 10. End-to-end verification

### Test 1 — Browser access

Open the Web App Service **Overview** page and select its **Default domain**.

Expected: the landing page loads over HTTPS. In this demo, inbound access is public by design for easier teaching. This does not prove the database path.

### Test 2 — Query Azure SQL through VNet Integration

Open:

```text
https://<YOUR_WEB_APP_NAME>.azurewebsites.net/health/db
```

Expected response:

```json
{
  "status": "connected",
  "message": "Azure SQL reached over App Service VNet Integration",
  "path": "App Service -> VNet Integration -> Azure SQL Private Endpoint"
}
```

The exact JSON formatting may vary. The key proof is HTTP `200` and the message returned from the SQL table.

### Test 3 — Verify the integration subnet

1. Open the Web App Service → **Networking** → **VNet Integration**.
2. Capture the connected VNet and integration subnet.
3. Open the VNet → **Subnets**.
4. Capture the subnet delegation to `Microsoft.Web/serverFarms`.

### Test 4 — Verify the Private Endpoint

1. Open `pe-sql-vnet-demo`.
2. Capture provisioning state and connection state.
3. Open its network interface and record the private IP.
4. Open the Private DNS zone `privatelink.database.windows.net`.
5. Confirm the VNet link and relevant DNS record.

### Test 5 — Verify SQL is private-only

1. Open the SQL logical server → **Networking**.
2. Confirm the Private Endpoint is configured and approved.
3. Confirm public network access is disabled after private connectivity has been validated.
4. From the Web App Service, repeat `/health/db`; it should continue returning HTTP `200`.

### Test 6 — Prove the Web App Service is not VNet-injected

Capture the following together:

- Web App Service Overview and its App Service plan.
- VNet Integration blade showing the selected VNet/subnet.
- VNet subnet page showing `Microsoft.Web/serverFarms` delegation.
- Architecture/resource inventory showing the Web App Service is an App Service resource, not a VM or service deployed as a resource inside the VNet.
- Azure SQL private endpoint and successful query evidence.

**Interpretation:** Integration is an outbound networking feature for App Service. The Web App Service is not deployed into the integration subnet; the subnet supplies the network path.

---

## 11. Troubleshooting

### `/health/db` returns `503`

1. Open Web App Service → **Monitoring → Log stream** or supported application logs.
2. Verify all `SQL_*` settings and the server FQDN.
3. Confirm VNet Integration is connected to `vnet-app-integration`.
4. Confirm `snet-appservice-integration` is delegated to `Microsoft.Web/serverFarms`.
5. Confirm the Private Endpoint is approved and provisioned.
6. Verify `privatelink.database.windows.net` is linked to the VNet and the DNS record is correct.
7. Confirm the SQL database, table, user, and password are correct.
8. Check outbound routes, NSGs, firewalls, and SQL networking configuration.

### DNS does not resolve privately

- Use the normal SQL FQDN (`<server>.database.windows.net`), not a hard-coded private IP.
- Confirm the Private DNS zone name is `privatelink.database.windows.net`.
- Confirm the VNet link exists.
- Check custom DNS, forwarding rules, and DNS caching.
- Use App Service supported diagnostics where available; a local VM's DNS result does not alone prove the Web App Service uses the same path.

### ODBC driver error

- `pyodbc` requires a compatible native ODBC driver.
- Use a supported custom container with Microsoft ODBC Driver 18 installed, or another supported database driver/runtime combination.
- Do not assume the standard Python App Service image has the ODBC driver installed.

### Timeout or connection refused

- Confirm SQL Private Endpoint provisioning and approval.
- Verify the server's public network access setting and private endpoint.
- Check DNS resolution from the App Service environment where supported.
- Review routes, NSGs, firewalls, and App Service plan compatibility.
- Verify TCP 1433 is permitted along the private path.

---

## 12. Evidence checklist

Save screenshots and test output from the actual deployment:

- [ ] Resource group resource inventory.
- [ ] VNet address space and subnet list.
- [ ] Integration subnet delegation to `Microsoft.Web/serverFarms`.
- [ ] Web App Service VNet Integration blade showing connected state.
- [ ] Azure SQL Private Endpoint overview showing Succeeded/Approved.
- [ ] Private Endpoint NIC showing its private IP.
- [ ] Private DNS zone and VNet link.
- [ ] SQL networking page showing public access disabled.
- [ ] Successful `/health/db` response with HTTP `200` and the database message.
- [ ] Application log evidence of a successful query (without secrets).
- [ ] Resource inventory confirming no App Service VNet injection and no PostgreSQL delegated subnet was used.

Redact subscription IDs, tenant IDs, credentials, tokens, and other sensitive details before sharing.

## 13. Production readiness

- [ ] Use a supported App Service plan and integration subnet size.
- [ ] Keep the integration subnet dedicated and delegated correctly.
- [ ] Use private endpoints and private DNS for private SQL access.
- [ ] Disable SQL public network access where required by the security design.
- [ ] Use managed identity and Microsoft Entra authentication where supported; otherwise use a secure secret store.
- [ ] Validate TLS certificates; do not set `TrustServerCertificate=yes` as a shortcut.
- [ ] Apply least-privilege database permissions.
- [ ] Review custom DNS, outbound routes, forced tunneling, and egress firewall policy.
- [ ] Enable logs, metrics, alerts, and retention.
- [ ] Test scale-out, deployment rollback, SQL failover, and recovery.
- [ ] Review costs and remove resources after the lab.

## 14. Cleanup

1. Save the evidence pack.
2. Open **Resource groups** → `rg-app-vnet-integration`.
3. Select **Delete resource group** and confirm.

Only delete the dedicated lab resource group if it contains no shared resources. Delete only lab resources if any shared VNet or DNS zone was reused.

## 15. Official Microsoft documentation

- [App Service VNet Integration overview](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [Configure regional VNet Integration](https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-enable)
- [Azure SQL Private Link and private endpoints](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
- [Private DNS zones for Azure Private Endpoint](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

Verify current regional support, plan/SKU requirements, subnet sizing, portal labels, and database driver installation requirements before deployment.

---

## 16. Lab completion record

- Resource group: `rg-app-vnet-integration`
- Region: `Central India`
- Web App Service: `________________`
- App Service plan/SKU: `________________`
- VNet Integration status: `________________`
- Integration subnet: `snet-appservice-integration`
- Subnet delegation: `Microsoft.Web/serverFarms`
- SQL server FQDN: `________________`
- Private Endpoint IP: `________________`
- Private DNS zone/VNet link: `________________`
- SQL public network access disabled: `Yes / No`
- `/health/db` status: `________________`
- Query result: `________________`
- App Service VNet-injected: `No`
- App Service VNet Integration configured: `Yes`

### Pass condition

The Web App Service shows successful regional VNet Integration to the dedicated delegated subnet; Azure SQL is reached through its Private Endpoint and private DNS; `/health/db` returns HTTP `200` with the database row; and the Web App Service itself is not VNet-injected.

**Final teaching takeaway:** This is **VNet Integration without VNet injection**. The App Service remains outside the VNet's resource address space, while its supported outbound traffic can reach private resources through the integration subnet.
