# Azure VNet Injection — End-to-End Demo (Without App Service VNet Integration)

> **Goal:** Teach and prove Azure **VNet injection** as a deployment model where a supported Azure service is deployed into a customer-managed VNet/subnet. This lab uses **Azure Database for PostgreSQL Flexible Server with private VNet access**.
>
> **Explicit scope:** This demo does **not** use Azure App Service VNet Integration. There is no Web App Service integration subnet and no `Microsoft.Web/serverFarms` delegation in this lab. PostgreSQL Flexible Server is deployed into its own delegated subnet.

This is a production-style learning lab. It does not claim that resources have already been deployed. Follow the portal steps and capture evidence from your own subscription.

---

## 1. Learning outcomes

By completing this lab, you will learn to:

1. Explain VNet injection and how it differs from App Service VNet Integration.
2. Deploy PostgreSQL Flexible Server using private VNet access.
3. Create and delegate a dedicated subnet to `Microsoft.DBforPostgreSQL/flexibleServers`.
4. Configure private DNS so the database hostname resolves privately.
5. Prove database connectivity from a client VM inside the VNet.
6. Verify that public database access is not enabled for this private-only architecture.
7. Troubleshoot subnet delegation, DNS, routing, NSG, and database connectivity issues.

## 2. What “VNet injection” means in this demo

For this lab, **VNet injection** means that PostgreSQL Flexible Server is deployed with private VNet access into a subnet in your VNet. The database uses that delegated subnet rather than relying on a public database endpoint.

> Azure uses different networking models across services. This guide uses PostgreSQL Flexible Server private VNet access as the concrete example of a service deployed into a delegated subnet. Do not assume every Azure service uses the same injection model or subnet delegation.

### VNet injection vs. VNet Integration vs. Private Endpoint

| Feature | Meaning | Used in this demo? |
|---|---|---|
| **VNet injection / private VNet deployment** | The supported service is deployed into a customer VNet subnet | **Yes — PostgreSQL Flexible Server** |
| **App Service VNet Integration** | Gives an App Service an outbound path into a VNet through a dedicated integration subnet | **No** |
| **Private Endpoint** | Creates a private IP network interface in a VNet to access a supported service over Private Link | **No** |
| **VNet peering** | Connects two VNets at the network layer | **No** |

The database has private VNet connectivity. A VM in the same VNet connects to it using its private FQDN. This proves the private network path without introducing App Service VNet Integration.

---

## 3. Architecture

```text
                   Administrator
                 Azure Portal / CLI
                         |
                         v
+------------------------------------------------------------------+
| Azure subscription                                               |
| Resource group: rg-vnet-injection-demo                           |
|                                                                  |
| VNet: vnet-injection-demo                                        |
| Address space: 10.40.0.0/16                                      |
|                                                                  |
|  +-------------------------------+                               |
|  | snet-postgres                 |                               |
|  | 10.40.1.0/24 (example)        |                               |
|  | Delegation:                   |                               |
|  | Microsoft.DBforPostgreSQL/    |                               |
|  | flexibleServers               |                               |
|  |                               |                               |
|  | PostgreSQL Flexible Server    |                               |
|  | Private VNet access           |                               |
|  +---------------+---------------+                               |
|                  |                                               |
|                  | Private DNS zone                              |
|                  | linked to VNet                                |
|                  |                                               |
|  +---------------v---------------+                               |
|  | snet-client                   |                               |
|  | 10.40.2.0/24 (example)        |                               |
|  |                               |                               |
|  | Ubuntu test VM                |                               |
|  | psql / DNS lookup / TCP test  |                               |
|  +-------------------------------+                               |
+------------------------------------------------------------------+

Test VM -> private DNS -> PostgreSQL private address
No App Service Integration subnet, no Private Endpoint, no VNet peering.
```

### Packet flow

1. The test VM sends a database connection to the PostgreSQL server's FQDN on TCP port `5432`.
2. The VNet's configured DNS path resolves the server FQDN to the private database address.
3. Traffic stays on the private Azure network path to the PostgreSQL Flexible Server.
4. PostgreSQL authenticates the database user and returns the query result.

**Evidence goal:** DNS resolves privately, the client VM can run a SQL query, and the server's networking configuration confirms private VNet access.

---

## 4. Resource plan

This example uses **Central India**. Confirm service availability and capacity for your subscription before deploying.

| Resource | Name | Example configuration |
|---|---|---|
| Resource group | `rg-vnet-injection-demo` | Central India |
| Virtual network | `vnet-injection-demo` | `10.40.0.0/16` |
| PostgreSQL subnet | `snet-postgres` | `10.40.1.0/24`, delegated |
| Client subnet | `snet-client` | `10.40.2.0/24` |
| Private DNS zone | Created/selected by PostgreSQL private networking wizard | Linked to `vnet-injection-demo` |
| PostgreSQL Flexible Server | `pg-injection-demo-<unique>` | Private VNet access |
| Test VM | `vm-injection-client` | Ubuntu; no public IP preferred |

These are example IP ranges. Ensure they do not overlap with existing VNets, VPN address spaces, or on-premises networks.

### Prerequisites

- Azure subscription with permission to create VNets, subnets, VMs, PostgreSQL Flexible Server, and DNS resources.
- A region and subscription that support the selected PostgreSQL private networking configuration.
- An approved private administration method such as Azure Bastion or an existing private jump host.
- Secure handling for administrator and database credentials.
- Budget awareness: VM and PostgreSQL resources can incur charges while running.

---

## 5. Create the resource group and VNet in Azure Portal

### 5.1 Resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Choose your subscription.
4. Name: `rg-vnet-injection-demo`.
5. Region: **Central India**.
6. Select **Review + create** → **Create**.

### 5.2 Create the VNet

1. Search **Virtual networks** → **Create**.
2. Select `rg-vnet-injection-demo`.
3. Name: `vnet-injection-demo`.
4. Region: Central India.
5. Address space: `10.40.0.0/16`.
6. Create these subnets:
   - `snet-postgres`: `10.40.1.0/24`
   - `snet-client`: `10.40.2.0/24`
7. Select **Review + create** → **Create**.

### 5.3 Delegate the database subnet

1. Open `vnet-injection-demo` → **Subnets**.
2. Open `snet-postgres`.
3. Under **Subnet delegation**, select `Microsoft.DBforPostgreSQL/flexibleServers`.
4. Save.

Do not place the test VM in `snet-postgres`. The database subnet is dedicated to PostgreSQL Flexible Server and must not be shared with unrelated workloads.

Keep `snet-client` separate. It does not need the PostgreSQL delegation.

---

## 6. Create PostgreSQL Flexible Server with private VNet access

> Portal labels and available choices can change. Use the private VNet access option supported for PostgreSQL Flexible Server in your region, and follow current Microsoft documentation.

1. Search **Azure Database for PostgreSQL flexible servers**.
2. Select **Create**.
3. On **Basics**:
   - Resource group: `rg-vnet-injection-demo`
   - Server name: `pg-injection-demo-<unique>`
   - Region: Central India
   - PostgreSQL version: choose a currently supported version
   - Compute/storage: choose an appropriate lab size
   - Configure administrator credentials securely
4. On **Networking**:
   - Select **Private access (VNet Integration)** / private VNet access (portal wording may vary).
   - VNet: `vnet-injection-demo`
   - Subnet: `snet-postgres`
   - Private DNS zone: create or select the zone required by the wizard.
   - Ensure the private DNS zone is linked to `vnet-injection-demo`.
   - Do not enable public network access for this private-only lab.
5. Review + create.
6. Wait for deployment to complete.

### Capture this evidence

Open the PostgreSQL Flexible Server resource and record:

- Server name and provisioning state.
- Networking mode.
- VNet and delegated subnet.
- Private DNS zone.
- Server FQDN.
- Private address details, if displayed.

**Proof checkpoint A:** The database server is deployed with private VNet access, using the dedicated PostgreSQL-delegated subnet. This is the central VNet injection/private deployment concept in the demo.

---

## 7. Create a client VM inside the VNet

The client VM is a testing tool, not part of the database injection mechanism.

1. Search **Virtual machines** → **Create**.
2. Basics:
   - Resource group: `rg-vnet-injection-demo`
   - Name: `vm-injection-client`
   - Region: Central India
   - Image: Ubuntu Server 24.04 LTS or another approved Ubuntu image
   - Select an appropriate small lab size
   - Configure SSH key or approved authentication
3. Networking:
   - VNet: `vnet-injection-demo`
   - Subnet: `snet-client`
   - Public IP: **None preferred**
   - Configure the NIC/subnet NSG according to your policy.
4. Create the VM.
5. Connect using Azure Bastion or your approved private administration path.

If Bastion is needed, deploy it using the current Azure Bastion requirements. Bastion is for administrative access; it is not the database connection path being demonstrated.

---

## 8. Install a PostgreSQL client

On `vm-injection-client`, install the PostgreSQL client using an approved outbound package repository path:

```bash
sudo apt-get update
sudo apt-get install -y postgresql-client dnsutils netcat-openbsd
```

If the VM has no outbound package access, use your organization's approved repository/mirror or provisioning method. Do not add a public IP or broad inbound rules just to make the database test work.

---

## 9. Prove private DNS resolution

From the client VM, use the FQDN shown in the PostgreSQL portal. Replace the placeholder:

```bash
DB_HOST="pg-injection-demo-<unique>.<region>.postgres.database.azure.com"
getent hosts "$DB_HOST"
```

You can also try:

```bash
nslookup "$DB_HOST"
```

Expected: the server name resolves through the configured private DNS path to a private address for this private VNet deployment.

Do not guess the DNS zone name or record format. Use the actual server FQDN and the zone configured by the PostgreSQL networking wizard.

### Verify the DNS zone in the portal

1. Open the private DNS zone selected for the server.
2. Open **Virtual network links**.
3. Confirm there is a link to `vnet-injection-demo`.
4. Open **Record sets** and verify the database record as applicable.

A DNS result alone does not prove the database accepts connections. Continue to the SQL test.

---

## 10. Connect to PostgreSQL and run a query

Use the server FQDN, database name, and credentials configured during server creation. Do not place a password directly in shell history or commit it to a file.

A typical interactive command is:

```bash
psql "host=<SERVER_FQDN> port=5432 dbname=postgres user=<ADMIN_USER> sslmode=require"
```

Enter the password when prompted. Depending on the server configuration and authentication mode, the username format may need to follow the portal's displayed requirements.

Once connected, run:

```sql
SELECT version();
SELECT current_database();
SELECT inet_server_addr();
```

The precise output of `inet_server_addr()` depends on the server's networking implementation. Treat it as supplemental evidence; the primary proof is the configured private networking mode, private DNS resolution, and successful SQL query.

Create a teaching database and table:

```sql
CREATE DATABASE injectiondemo;
```

Exit and reconnect to the `injectiondemo` database, then run:

```sql
CREATE TABLE IF NOT EXISTS demo_status (
    id integer PRIMARY KEY,
    message text NOT NULL
);

INSERT INTO demo_status (id, message)
VALUES (1, 'Database reached through private VNet connectivity')
ON CONFLICT (id) DO UPDATE SET message = EXCLUDED.message;

SELECT * FROM demo_status;
```

Expected: the final query returns the row with the message:

```text
Database reached through private VNet connectivity
```

Use an appropriately privileged account for setup and a least-privilege account for application access.

---

## 11. Evidence checklist

Capture screenshots or terminal output from your real Azure environment:

- [ ] Resource group overview showing the lab resources.
- [ ] VNet overview showing `10.40.0.0/16`.
- [ ] Subnet configuration showing `snet-postgres` delegation to `Microsoft.DBforPostgreSQL/flexibleServers`.
- [ ] PostgreSQL Flexible Server Overview showing provisioning succeeded.
- [ ] PostgreSQL Networking blade showing private VNet access, VNet and subnet.
- [ ] Private DNS zone and its VNet link.
- [ ] DNS lookup from `vm-injection-client` showing private resolution.
- [ ] Successful `psql` connection and `SELECT version();`.
- [ ] Successful query showing the row inserted into `demo_status`.
- [ ] PostgreSQL networking settings showing public network access is not enabled for this design.
- [ ] VNet subnet list showing no App Service integration subnet was created.
- [ ] Resource inventory confirming no App Service VNet Integration or Private Endpoint was used.

Redact subscription IDs, tenant IDs, usernames, server names if sensitive, public IPs, passwords, tokens, and other sensitive information before sharing.

## 12. What proves VNet injection without VNet Integration?

| Claim | Evidence |
|---|---|
| Database uses private VNet deployment | PostgreSQL Networking blade shows private VNet access and selected VNet/subnet |
| Correct subnet delegation is configured | `snet-postgres` delegates to `Microsoft.DBforPostgreSQL/flexibleServers` |
| Client uses private DNS | FQDN lookup resolves through the linked private DNS configuration to a private address |
| Private database path works | `psql` connects and SQL query returns the expected row |
| Database is not publicly exposed in this design | Portal shows public network access disabled |
| App Service VNet Integration is not used | No App Service resource or `Microsoft.Web/serverFarms` integration subnet exists |
| Private Endpoint is not used | No Private Endpoint resource exists for this connection |

The strongest proof combines the portal configuration with successful DNS and SQL tests. Do not claim a live deployment until you have captured actual evidence.

---

## 13. Troubleshooting

### Subnet cannot be selected

- Confirm `snet-postgres` is delegated to `Microsoft.DBforPostgreSQL/flexibleServers`.
- Confirm the subnet is not already used by incompatible resources.
- Check region support, subscription restrictions, address capacity, and current service requirements.

### DNS resolves publicly or does not resolve

- Verify you are using the exact FQDN shown in the PostgreSQL portal.
- Confirm the correct private DNS zone was selected.
- Verify the zone has a VNet link to `vnet-injection-demo`.
- Check whether the VM uses a custom DNS server or DNS forwarder.
- Wait for DNS cache expiry after changing records or links.

### `psql` connection times out

1. Verify the database provisioning state is succeeded.
2. Confirm the client VM is in `vnet-injection-demo`.
3. Confirm DNS resolves to the expected private address.
4. Check NSGs, routes, and firewall policy.
5. Check the database subnet and private access configuration.
6. Verify TCP `5432` is allowed where required.
7. Confirm the client is using the actual FQDN and correct port.

### Authentication fails

- Verify the administrator/user name and password.
- Check whether the account uses password or an alternative supported authentication method.
- Confirm the database user has access to the requested database.
- Do not work around an authentication failure by enabling public database access.

### Cannot install the client package

The VM may not have outbound access to package repositories. Use an approved package mirror, image, or provisioning process. This is separate from the private database network path.

---

## 14. Production hardening

- [ ] Use private VNet access where required by the security design.
- [ ] Keep the PostgreSQL subnet dedicated and correctly delegated.
- [ ] Review subnet size, service limits, and regional availability.
- [ ] Use TLS and secure certificate validation.
- [ ] Use least-privilege database accounts and managed/approved secret storage.
- [ ] Configure private DNS ownership, links, and any custom DNS forwarding.
- [ ] Restrict administrative access to Bastion or an approved private path.
- [ ] Configure backups, restore testing, patching, maintenance, and disaster recovery.
- [ ] Enable appropriate monitoring, diagnostic logs, alerting, and retention.
- [ ] Review network security rules and routing with your network/security team.
- [ ] Test failure, recovery, and operational runbooks before production approval.
- [ ] Review costs and delete the lab when finished.

---

## 15. Cleanup

1. Save the evidence pack.
2. Open **Resource groups** → `rg-vnet-injection-demo`.
3. Select **Delete resource group**.
4. Type the resource group name and confirm.

Only delete the dedicated lab resource group if it contains no shared resources. If you reused a shared VNet, DNS zone, or other resource, delete only the lab resources you created.

---

## 16. Official Microsoft references

- [Private networking for Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private)
- [Azure Database for PostgreSQL Flexible Server documentation](https://learn.microsoft.com/en-us/azure/postgresql/)
- [Azure Virtual Network overview](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview)
- [Azure Private Endpoint overview — comparison reference](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)

Review current documentation for supported regions, subnet delegation, DNS behavior, portal labels, and service limits before deployment.

---

## 17. Lab completion record

Fill in after completing the lab:

- Resource group: `rg-vnet-injection-demo`
- Region: `Central India`
- VNet: `vnet-injection-demo`
- PostgreSQL server: `________________`
- PostgreSQL FQDN: `________________`
- Delegated subnet: `snet-postgres`
- Private DNS zone: `________________`
- DNS lookup result/private IP: `________________`
- SQL connection successful: `Yes / No`
- Demo table query successful: `Yes / No`
- Public database access disabled: `Yes / No`
- App Service VNet Integration used: `No`
- Private Endpoint used: `No`
- Evidence folder/location: `________________`

### Pass condition

The PostgreSQL Flexible Server is configured for private VNet access in its dedicated delegated subnet; the client VM resolves its FQDN to a private address and successfully executes SQL; public database access is disabled for the private-only design; and the lab uses neither App Service VNet Integration nor a Private Endpoint.

**Final teaching takeaway:** In this demo, VNet injection/private VNet deployment is the database's network placement model. There is no App Service VNet Integration. The VM is simply a private client used to validate DNS and database connectivity.
