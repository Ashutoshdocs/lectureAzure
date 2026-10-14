# Azure App Service VNet Integration — End-to-End Teaching Demo

> **Objective:** Teach, build, and verify Azure App Service VNet Integration by deploying an Azure Web App Service that sends outbound traffic into an Azure Virtual Network and connects to a private Azure Database for PostgreSQL Flexible Server.
>
> **Teaching message:** VNet Integration gives an App Service an outbound path into a VNet. It does **not** make the Web App Service privately reachable inbound by itself.

This is a production-style learning lab, not a claim that resources are already deployed. Complete the steps in your own Azure subscription and capture the evidence listed below.

---

## 1. What you will learn

By the end of this demo, you should be able to explain and prove:

1. What Azure App Service VNet Integration does.
2. Why App Service Integration requires a dedicated subnet delegated to `Microsoft.Web/serverFarms`.
3. How an App Service connects to a private PostgreSQL Flexible Server address through a VNet.
4. How private DNS resolves a database hostname to a private IP.
5. How to distinguish **VNet Integration**, **VNet Injection**, and **Private Endpoint**.
6. How to verify the route from the application to the database, and troubleshoot a failed connection.
7. Which controls are needed before adapting the design to production.

## 2. Architecture

```text
                       User / Browser
                             |
                             | HTTPS (public inbound in this demo)
                             v
                  +------------------------+
                  | Azure Web App Service  |
                  | web-vnet-demo          |
                  | Flask Student Portal   |
                  +-----------+------------+
                              |
                              | OUTBOUND VNet Integration
                              | App Service -> delegated integration subnet
                              v
+--------------------------------------------------------------------------+
| Azure Virtual Network: vnet-app-demo  | Address space: 10.30.0.0/16       |
|                                                                          |
|  +--------------------------------+   +-------------------------------+  |
|  | snet-appservice                 |   | snet-postgres                 |  |
|  | 10.30.1.0/26 (example)         |   | 10.30.2.0/24 (example)        |  |
|  | Delegation:                    |   | Delegation:                   |  |
|  | Microsoft.Web/serverFarms      |   | Microsoft.DBforPostgreSQL/    |  |
|  |                                |   | flexibleServers               |  |
|  | App Service integration path   |   | PostgreSQL Flexible Server   |  |
|  +--------------------------------+   | Private VNet access           |  |
|                                       +---------------+---------------+  |
|                                                       |                  |
|                                      Private DNS zone |                  |
|                                      linked to VNet    |                  |
+-------------------------------------------------------|------------------+
                                                        |
                                                        v
                                      PostgreSQL private IP / TCP 5432
```

### Traffic flows

**Inbound browser request**

1. The browser requests the Web App Service URL over HTTPS.
2. Azure App Service receives the request.
3. The application handles the page/API request.

This demo leaves inbound access to the Web App Service public so the learner can easily open it in a browser. That public inbound path is separate from VNet Integration.

**Outbound database request**

1. The Web App Service code opens a connection to the PostgreSQL hostname on TCP port `5432`.
2. App Service VNet Integration sends supported outbound traffic through the configured integration subnet into `vnet-app-demo`.
3. DNS resolves the database hostname to the private address configured for the PostgreSQL Flexible Server.
4. PostgreSQL receives the connection through its private VNet networking configuration.
5. The database returns the query result to the Web App Service.

**Key proof:** The application works, the database hostname resolves privately from the integrated app environment, and a query to PostgreSQL succeeds without using a public database endpoint.

> Address ranges above are examples. Check your existing networks before choosing them. Use non-overlapping ranges and the currently supported subnet sizing for your App Service plan and integration configuration.

---

## 3. Understand the three Azure networking concepts

| Concept | What it does | Traffic direction / placement |
|---|---|---|
| **App Service VNet Integration** | Gives an App Service outbound connectivity to resources reachable through a VNet | App Service outbound traffic enters a dedicated delegated integration subnet |
| **PostgreSQL Flexible Server private VNet access (VNet injection)** | Deploys the database with private network connectivity in a delegated subnet | Database is placed in the VNet's delegated database subnet |
| **Private Endpoint** | Creates a private IP network interface in your VNet for a supported service | Consumers connect to that private IP; used for private access to a service endpoint |

Do not confuse them:

- App Service VNet Integration does **not** create a private inbound IP for the Web App Service.
- VNet Integration does **not** automatically make every outbound request private. Public destinations may still be reached through the configured egress path.
- PostgreSQL Flexible Server using private VNet access is deployed into its delegated subnet; that subnet cannot be shared with App Service Integration.
- A Private Endpoint is a separate resource and is not required for this specific PostgreSQL VNet-injected architecture.
- If you need private inbound access to the Web App Service, evaluate an App Service Private Endpoint separately. Configure DNS and access restrictions appropriately; do not assume VNet Integration provides inbound privacy.

---

## 4. Lab design and resource names

Use a single region and a dedicated resource group. This example uses **Central India**.

| Resource | Example name | Configuration |
|---|---|---|
| Resource group | `rg-vnet-integration-demo` | Central India |
| VNet | `vnet-app-demo` | `10.30.0.0/16` |
| App Service integration subnet | `snet-appservice` | Example `10.30.1.0/26`; delegate to `Microsoft.Web/serverFarms` |
| PostgreSQL subnet | `snet-postgres` | Example `10.30.2.0/24`; delegate to `Microsoft.DBforPostgreSQL/flexibleServers` |
| PostgreSQL private DNS zone | Use the zone suggested/required by the portal for the selected PostgreSQL private networking mode | Link to `vnet-app-demo` |
| PostgreSQL Flexible Server | `pg-vnet-demo-<unique>` | Private VNet access; no public access |
| App Service plan | `asp-vnet-demo` | Linux plan on a SKU that supports VNet Integration |
| Web App Service | `web-vnet-demo-<unique>` | Linux runtime supported by the selected plan |
| Application | `Student Portal` | Flask demo with a database connectivity check |

Use a globally unique Web App Service name. The exact available SKUs and subnet sizing requirements can change, so verify them in the portal and official documentation before deployment.

### Prerequisites

- Azure subscription and permission to create App Service, App Service plan, VNet/subnets, PostgreSQL Flexible Server, and private DNS resources.
- App Service plan/SKU that supports regional VNet Integration.
- PostgreSQL Flexible Server configuration that supports private VNet access in your selected region/subscription.
- An approved way to administer the environment.
- A secure way to store database credentials. Do not commit passwords to Git or embed them in the application source.
- Budget awareness: App Service plan and PostgreSQL Flexible Server can incur charges while provisioned.

---

## 5. Azure Portal UI — create the network

### 5.1 Create a resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Select the subscription.
4. Enter `rg-vnet-integration-demo`.
5. Select **Central India**.
6. Select **Review + create** → **Create**.

### 5.2 Create the VNet

1. Search **Virtual networks** → **Create**.
2. Resource group: `rg-vnet-integration-demo`.
3. Name: `vnet-app-demo`.
4. Region: Central India.
5. Address space: `10.30.0.0/16`.
6. Create the subnets:
   - `snet-appservice`: `10.30.1.0/26` (example only; confirm the minimum size required by the selected App Service plan and integration mode).
   - `snet-postgres`: `10.30.2.0/24` (example only; use the sizing required by PostgreSQL and allow room for service needs).
7. Create the VNet.

### 5.3 Delegate each subnet correctly

Open `vnet-app-demo` → **Subnets**.

For `snet-appservice`:

1. Open the subnet.
2. Set **Subnet delegation** to `Microsoft.Web/serverFarms`.
3. Save.

For `snet-postgres`:

1. Open the subnet.
2. Set **Subnet delegation** to `Microsoft.DBforPostgreSQL/flexibleServers`.
3. Save.

The two subnets must remain separate. Do not place the App Service integration subnet and PostgreSQL server in the same subnet.

---

## 6. Create PostgreSQL Flexible Server with private VNet access

> Portal labels and supported networking choices can change. Follow the private networking option for PostgreSQL Flexible Server and the current Microsoft documentation for the region and server version you select.

1. Search **Azure Database for PostgreSQL flexible servers** → **Create**.
2. Select `rg-vnet-integration-demo` and Central India.
3. Enter a unique server name such as `pg-vnet-demo-<unique>`.
4. Choose a supported PostgreSQL version, compute tier, and storage size suitable for the lab.
5. Configure administrator credentials securely and store them in an approved secret store.
6. On **Networking**, select the **Private access (VNet Integration)** option for PostgreSQL Flexible Server (portal wording may vary).
7. Select:
   - Virtual network: `vnet-app-demo`
   - Subnet: `snet-postgres`
   - Private DNS zone: create or select the zone required by the wizard and link it to `vnet-app-demo`.
8. Ensure the server is not configured for public network access for this private-only demo.
9. Review + create → Create.
10. After deployment, open the server and record:
    - Provisioning state
    - Networking mode
    - Private DNS zone
    - Server FQDN
    - Private IP/network details if exposed in the portal

### Why private DNS matters

The application should connect using the PostgreSQL **FQDN**, not a hard-coded private IP. The private DNS zone makes the server hostname resolve to the correct private address for clients using the linked VNet DNS configuration.

Do not guess the zone name. Use the zone shown or required by the PostgreSQL wizard and current Microsoft documentation. Confirm the VNet link exists.

### Create a small database and table

Use an approved client path for database administration. Depending on your design, connect from a temporary admin VM inside the VNet or use an approved PostgreSQL client path. Do not open public database access just for convenience.

Example SQL:

```sql
CREATE DATABASE studentportal;
```

Connect to the `studentportal` database and run:

```sql
CREATE TABLE IF NOT EXISTS demo_status (
    id integer PRIMARY KEY,
    message text NOT NULL
);

INSERT INTO demo_status (id, message)
VALUES (1, 'PostgreSQL reached over private VNet connectivity')
ON CONFLICT (id) DO UPDATE SET message = EXCLUDED.message;

SELECT * FROM demo_status;
```

The SQL account used by the application should have only the privileges required for the demo.

If you need an administration VM, put it in a separate subnet, restrict access, and remove it after the lab. Avoid opening PostgreSQL to the internet.

---

## 7. Create the Azure Web App Service

1. Search **App Services** → **Create** → **Web App**.
2. Basics:
   - Resource group: `rg-vnet-integration-demo`
   - Name: `web-vnet-demo-<unique>`
   - Publish: Code
   - Runtime stack: choose a supported Python version for the selected plan
   - Operating system: Linux
   - Region: Central India
3. Create a new App Service plan `asp-vnet-demo`.
4. Select a plan/SKU that supports regional VNet Integration. Do not assume every Free/Shared SKU supports it.
5. Review + create → Create.
6. Open the Web App Service after deployment.

### Configure VNet Integration

1. In the Web App Service, open **Networking**.
2. Find **VNet Integration** / **Outbound traffic configuration** (the exact portal placement can vary).
3. Select **Add VNet** or **Configure VNet Integration**.
4. Choose `vnet-app-demo`.
5. Select `snet-appservice`.
6. Save and wait for the integration status to show connected/configured.

**Do not select `snet-postgres`.** PostgreSQL owns its delegated subnet; App Service Integration needs its own dedicated subnet delegated to `Microsoft.Web/serverFarms`.

### Configure application settings securely

In Web App Service → **Settings → Environment variables** (or **Configuration**, depending on portal experience), add settings such as:

- `DB_HOST`: PostgreSQL Flexible Server FQDN from the portal.
- `DB_NAME`: `studentportal`.
- `DB_USER`: database application username.
- `DB_PASSWORD`: use a secret reference or approved secret-management mechanism; for a short-lived lab, enter it through the portal and do not store it in Git.
- `DB_PORT`: `5432`.

Save and restart the Web App Service if requested.

---

## 8. Deploy a minimal Flask Student Portal connectivity check

This example returns a simple status page and performs a small read query. It is designed to prove the network and DNS path, not to serve as a complete student-management system.

### `requirements.txt`

```text
Flask
gunicorn
psycopg[binary]
```

### `app.py`

```python
import os
from flask import Flask, jsonify
import psycopg

app = Flask(__name__)

def db_config():
    required = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError("Missing application settings: " + ", ".join(missing))

    return {
        "host": os.environ["DB_HOST"],
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.environ["DB_NAME"],
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
        "connect_timeout": 5,
        "sslmode": os.getenv("DB_SSLMODE", "require"),
    }

@app.get("/")
def home():
    return """
    <h1>Azure App Service VNet Integration Demo</h1>
    <p>Try <a href="/health/db">/health/db</a> to test PostgreSQL connectivity.</p>
    """

@app.get("/health/db")
def db_health():
    try:
        with psycopg.connect(**db_config()) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT message FROM demo_status WHERE id = 1")
                row = cur.fetchone()

        if not row:
            return jsonify(status="connected", detail="Query succeeded; no demo row found"), 200

        return jsonify(
            status="connected",
            detail=row[0],
            proof="Web App Service -> VNet Integration -> PostgreSQL private VNet access"
        ), 200

    except Exception:
        # Avoid returning credentials, host details, or exception text to anonymous users.
        app.logger.exception("Database health check failed")
        return jsonify(status="error", detail="Database connectivity check failed; inspect server logs"), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
```

### Configure the startup command

In Web App Service → **Configuration / General settings** or the runtime's startup configuration, set the startup command to:

```bash
gunicorn --bind 0.0.0.0:8000 app:app
```

Use the startup command and deployment mechanism supported by the selected App Service runtime. The example assumes `app.py` is at the deployed application root and contains the Flask variable `app`.

### Deploy the code

Choose one supported method:

- **Deployment Center** connected to a Git repository, or
- ZIP deployment / Azure CLI from a local project directory, or
- Your organization's CI/CD pipeline.

Keep the project files in one directory:

```text
student-portal/
├── app.py
└── requirements.txt
```

For an Azure CLI deployment from a machine with Azure CLI installed and authenticated:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az webapp deploy \
  --resource-group rg-vnet-integration-demo \
  --name "<YOUR_WEB_APP_NAME>" \
  --src-path app.zip \
  --type zip
```

Create `app.zip` from the **contents** of the application directory so `app.py` and `requirements.txt` are at the archive root. Confirm the app's runtime and deployment settings are compatible with this method.

---

## 9. End-to-end proof

### Test 1 — Browser can reach the Web App Service

Open the Web App Service's **Overview** page and select **Default domain**.

Expected: the Student Portal landing page loads over HTTPS.

This confirms inbound web access only. It does **not** prove database traffic uses VNet Integration.

### Test 2 — The application can query PostgreSQL

Open:

```text
https://<YOUR_WEB_APP_NAME>.azurewebsites.net/health/db
```

Expected response (example):

```json
{
  "status": "connected",
  "detail": "PostgreSQL reached over private VNet connectivity",
  "proof": "Web App Service -> VNet Integration -> PostgreSQL private VNet access"
}
```

The exact JSON formatting may differ. The success criteria are HTTP `200`, `"status": "connected"`, and the database message returned by the SQL query.

If the endpoint returns HTTP `503`, check application logs and follow the troubleshooting section. The app intentionally does not disclose internal exception details to anonymous callers.

### Test 3 — Verify VNet Integration in the portal

1. Open the Web App Service → **Networking**.
2. Open **VNet Integration**.
3. Capture the selected VNet and subnet.
4. Open `vnet-app-demo` → **Subnets**.
5. Capture `snet-appservice` and its `Microsoft.Web/serverFarms` delegation.

### Test 4 — Verify PostgreSQL private networking

1. Open PostgreSQL Flexible Server → **Networking**.
2. Confirm the private VNet access mode and selected VNet/subnet.
3. Confirm public access is not enabled for this private-only design.
4. Open the linked private DNS zone.
5. Verify the VNet link to `vnet-app-demo` and the server's DNS record as applicable.
6. Record the server FQDN and, where available, its private address.

### Test 5 — Prove DNS resolution from the integrated App Service environment

Use the App Service's supported diagnostic console (for example, **Development Tools → Advanced Tools (Kudu) → Debug console** when available) and execute:

```bash
getent hosts "$DB_HOST"
```

If that console does not expose the needed shell/network tools, use the platform's supported diagnostics or an approved test workload in the same VNet. Do not assume every App Service console includes `getent`, `nslookup`, `nc`, or `psql`.

Expected: the database FQDN resolves to the private address used by the PostgreSQL private networking configuration.

A DNS lookup alone does not prove a successful TCP/database session; combine it with Test 2.

### Test 6 — Capture database and application evidence

Capture the following after your deployment:

- Web App Service Overview with the app name and default domain (redact sensitive IDs).
- VNet Integration blade showing `vnet-app-demo` and `snet-appservice`.
- VNet subnet page showing the App Service delegation.
- PostgreSQL Networking blade showing private access and the delegated database subnet.
- Private DNS zone and VNet link.
- Successful `/health/db` response with HTTP `200`.
- Application logs showing the health endpoint succeeded (avoid logging secrets).
- Evidence that PostgreSQL public network access is disabled for this design.

**Strongest proof:** the app is integrated with the VNet, the PostgreSQL FQDN resolves privately from the integrated environment, PostgreSQL public access is disabled, and the app successfully executes a query.

---

## 10. Failure tests for teaching

Run one test at a time and restore the configuration immediately after each test.

| Test | Controlled change | Expected result |
|---|---|---|
| Wrong DB hostname | Temporarily change `DB_HOST` to an invalid hostname | `/health/db` returns `503`; logs show DNS/connection failure |
| Wrong database password | Use a known-invalid test password briefly | `/health/db` returns `503`; logs show authentication failure |
| Missing DNS link | In a disposable lab only, remove the VNet link or test using a separate unlinked VNet | Name resolution may fail or resolve incorrectly; restore the link |
| Wrong port | Temporarily set `DB_PORT` to an unused port | Connection times out or fails; endpoint returns `503` |
| Integration disconnected | In a disposable environment, disconnect integration and observe the impact | Private database connectivity should fail if there is no alternate route |
| Public database path | Verify the server is not publicly accessible | A connection from an unrelated external network should not reach the private-only database |

Do not conduct disruptive tests in a production environment. DNS caching, connection pooling, firewall rules, and platform behavior can affect the exact error and timing.

---

## 11. Troubleshooting

### `/health/db` returns `503`

1. Open Web App Service → **Monitoring → Log stream** or the supported application logs.
2. Confirm all `DB_*` settings are present and correct.
3. Verify the Web App Service VNet Integration status.
4. Confirm `snet-appservice` is delegated to `Microsoft.Web/serverFarms`.
5. Verify PostgreSQL is running and its private VNet configuration uses `snet-postgres`.
6. Verify the database name, user, password, port, and permissions.
7. Check private DNS zone links and hostname resolution.
8. Review NSGs, user-defined routes, firewall rules, and any forced-tunneling/egress configuration.
9. Confirm the App Service plan supports VNet Integration and the integration subnet meets current platform requirements.

### Hostname does not resolve to a private address

- Use the FQDN shown by PostgreSQL Flexible Server.
- Check the private DNS zone selected by the PostgreSQL wizard.
- Confirm the zone is linked to the VNet used by the application.
- Confirm the Web App Service is integrated with that VNet.
- Review any custom DNS server and routing configuration.
- Allow for DNS caching after a change.

### Integration cannot be configured

- Confirm the App Service plan/SKU supports regional VNet Integration.
- Confirm the VNet is compatible with the App Service plan's region and networking mode.
- Use a dedicated integration subnet with the required `Microsoft.Web/serverFarms` delegation.
- Ensure the subnet is not used by PostgreSQL or another incompatible resource.
- Check current minimum subnet size, subnet capacity, and platform restrictions.

### It works from a VM but not from App Service

A VM test alone does not prove the App Service has the same DNS settings, routes, or VNet Integration. Verify the integration configuration on the Web App Service itself, test DNS from the app environment where supported, and use the app's actual database health endpoint.

---

## 12. Production readiness checklist

- [ ] Select a supported App Service plan/SKU and correct integration subnet size.
- [ ] Keep the App Service integration subnet separate from all other delegated subnets.
- [ ] Keep the PostgreSQL server on private VNet access and disable public access when the design requires private-only connectivity.
- [ ] Use managed identity or an approved secret-management approach wherever supported; do not commit secrets to source control.
- [ ] Use TLS and validate certificates for database connections.
- [ ] Configure least-privilege database accounts.
- [ ] Use private DNS and document ownership of DNS zones and links.
- [ ] Review outbound routing behavior, NSGs, route tables, firewalls, and DNS forwarding.
- [ ] Enable appropriate application/database diagnostics, monitoring, alerting, and retention.
- [ ] Use availability, backup, restore, patching, and disaster-recovery plans appropriate to the workload.
- [ ] Restrict the health endpoint if it reveals operational information; this example deliberately returns only a generic error on failure.
- [ ] Test deployment, rollback, scale-out, failover, and recovery before production release.
- [ ] Review regional support, service limits, pricing, and security requirements.

---

## 13. Cleanup

To avoid ongoing charges:

1. Save your screenshots and notes.
2. If you deployed the lab into its own resource group, open **Resource groups** → `rg-vnet-integration-demo`.
3. Select **Delete resource group**.
4. Type the resource group name to confirm and delete.

If you reused shared networking, DNS, or other resources, delete only the resources created for this lab. Do not delete shared or production resources.

---

## 14. Official Microsoft documentation

- [Integrate your app with an Azure virtual network — App Service](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [Configure regional VNet Integration — App Service](https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-enable)
- [Private networking for Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private)
- [Azure Private Endpoint overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)

Review the current documentation for the exact portal labels, supported SKUs, subnet sizing, DNS behavior, and region-specific requirements before deploying.

---

## 15. Lab completion record

Fill this out using your actual Azure deployment:

- Resource group: `rg-vnet-integration-demo`
- Region: `Central India`
- Web App Service name: `________________`
- App Service plan/SKU: `________________`
- Integrated VNet/subnet: `________________`
- App Service integration status: `________________`
- PostgreSQL Flexible Server name/FQDN: `________________`
- PostgreSQL networking mode: `________________`
- Private DNS zone and VNet link: `________________`
- Resolved database private IP: `________________`
- `/health/db` HTTP status: `________________`
- Database query result: `________________`
- PostgreSQL public access disabled: `Yes / No`
- Evidence folder/location: `________________`

### Pass condition

The Web App Service has successful VNet Integration; the PostgreSQL hostname resolves to the private address from the integrated app environment; public database access is disabled for the private-only design; and the app's `/health/db` endpoint successfully queries the database and returns HTTP `200`.

**Final teaching takeaway:** App Service VNet Integration is primarily an **outbound connectivity feature**. PostgreSQL private VNet access places the database within a delegated subnet. Private Endpoint is a different mechanism and is used when a consumer needs a private IP to access a supported service.
