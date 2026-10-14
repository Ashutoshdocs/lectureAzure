# Azure Private Endpoint — End-to-End Teaching Demo

> **Goal:** Create an Azure Private Endpoint for an Azure Storage Account, prove that the service can be reached through a private IP in your VNet, and collect portal and command-line evidence showing how Private Link works.
>
> **Scope:** This lab uses Azure Blob Storage. It demonstrates **private inbound access from a VNet to a PaaS service**. It does not use App Service VNet Integration, VNet injection, Private Link Service, or VNet peering.

This is a production-style teaching lab, not a claim that resources have already been deployed. Capture screenshots and command output from your own Azure environment.

---

## 1. Learning outcomes

By completing this lab, you will be able to:

1. Explain Azure Private Endpoint and Azure Private Link.
2. Create a VNet and a dedicated subnet for a Private Endpoint.
3. Create a Storage Account and a Blob Private Endpoint.
4. Configure the `privatelink.blob.core.windows.net` private DNS zone.
5. Prove that the Storage Account hostname resolves to a private IP from a VM in the VNet.
6. Upload and download a blob over the private path.
7. Disable public network access and show that private connectivity continues to work.
8. Distinguish Private Endpoint from VNet Integration, VNet injection, and Private Link Service.

## 2. Key concepts

- **Private Endpoint:** A network interface with a private IP in your VNet. It connects privately to a supported Azure service.
- **Azure Private Link:** The underlying capability that carries traffic privately from the endpoint to the target service.
- **Private DNS zone:** Resolves the service hostname to the Private Endpoint's private IP for clients using the linked VNet's DNS configuration.
- **Private Link Service:** A different feature that lets a service provider publish their own service behind a Standard Internal Load Balancer. It is not needed for this Storage Account demo.
- **VNet Integration:** An outbound connectivity feature for supported services such as Azure App Service. It is not used here.

**Teaching takeaway:** A Private Endpoint gives a consumer a private IP address for a supported service. The service itself remains an Azure PaaS resource; it is not moved into your subnet.

---

## 3. Architecture

```text
                  Client VM inside Azure VNet
                  vm-pe-client
                         |
                         | DNS lookup:
                         | account.blob.core.windows.net
                         v
              Private DNS zone
              privatelink.blob.core.windows.net
                         |
                         | resolves to private IP
                         v
+----------------------------------------------------------------+
| VNet: vnet-private-endpoint-demo                               |
| Address space: 10.60.0.0/16                                    |
|                                                                |
|  +---------------------------+                                 |
|  | snet-client               |                                 |
|  | 10.60.1.0/24              |                                 |
|  | Ubuntu VM                 |                                 |
|  +---------------------------+                                 |
|                                                                |
|  +---------------------------+                                 |
|  | snet-private-endpoints    |                                 |
|  | 10.60.2.0/24              |                                 |
|  | Private Endpoint NIC      |                                 |
|  | Private IP e.g. 10.60.2.4 |                                 |
|  +-------------+-------------+                                 |
+----------------|-----------------------------------------------+
                 |
                 | Azure Private Link
                 v
       +----------------------------+
       | Azure Storage Account      |
       | Blob service               |
       | Public network access off  |
       +----------------------------+
```

### Request flow

1. The VM requests `https://<storage-account>.blob.core.windows.net`.
2. Private DNS resolves the normal Blob hostname through the Private Link DNS alias to the Private Endpoint's private IP.
3. The VM sends HTTPS traffic to that private IP.
4. Azure Private Link carries the traffic to the Storage Account's Blob service.
5. Azure Storage authorizes the request using the configured identity, SAS, or other supported authentication.
6. The blob operation succeeds over the private path.

DNS resolution and network connectivity do not replace Storage authorization. A private connection can work while an unauthenticated blob request is correctly rejected.

---

## 4. Resource plan

This example uses **Central India**. Confirm region availability and subscription capacity before deployment.

| Resource | Example name | Configuration |
|---|---|---|
| Resource group | `rg-private-endpoint-demo` | Central India |
| VNet | `vnet-private-endpoint-demo` | `10.60.0.0/16` |
| Client subnet | `snet-client` | `10.60.1.0/24` |
| Private Endpoint subnet | `snet-private-endpoints` | `10.60.2.0/24` |
| Client VM | `vm-pe-client` | Ubuntu, preferably no public IP |
| Storage Account | `stpedemo<unique>` | Standard GPv2 |
| Private Endpoint | `pe-blob-demo` | Target sub-resource: `blob` |
| Private DNS zone | `privatelink.blob.core.windows.net` | Linked to the VNet |

Storage Account names must be globally unique, lowercase, and contain only supported characters. Replace `<unique>` with a short unique suffix.

### Prerequisites

- Azure subscription and permissions to create VNets, VMs, Storage Accounts, Private Endpoints and DNS zones.
- A private administration path to the VM, such as Azure Bastion or an approved jump host.
- An approved way to authenticate to Storage, preferably Microsoft Entra ID with least-privilege RBAC.
- Budget awareness: VM, Bastion, Private Endpoint and Storage resources may incur charges.

---

## 5. Create the resource group and VNet

### 5.1 Resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Select your subscription.
4. Name: `rg-private-endpoint-demo`.
5. Region: Central India.
6. Select **Review + create** → **Create**.

### 5.2 VNet and subnets

1. Search **Virtual networks** → **Create**.
2. Resource group: `rg-private-endpoint-demo`.
3. Name: `vnet-private-endpoint-demo`.
4. Region: Central India.
5. Address space: `10.60.0.0/16`.
6. Create these subnets:
   - `snet-client`: `10.60.1.0/24`
   - `snet-private-endpoints`: `10.60.2.0/24`
7. Create the VNet.

For this lab, the Private Endpoint subnet does not need `Microsoft.Web/serverFarms` delegation. Do not reuse an App Service integration subnet for the Private Endpoint.

---

## 6. Create the Storage Account

1. Search **Storage accounts** → **Create**.
2. Basics:
   - Resource group: `rg-private-endpoint-demo`
   - Storage Account name: `stpedemo<unique>`
   - Region: Central India
   - Performance: Standard
   - Redundancy: choose an appropriate lab option, such as locally redundant storage if available
3. Keep the security configuration aligned with your organization's requirements.
4. Review + create → Create.
5. Open the Storage Account and record its name and Blob endpoint, usually:
   `https://<storage-account>.blob.core.windows.net/`

### Create a container

1. Open the Storage Account → **Data storage → Containers**.
2. Select **+ Container**.
3. Name it `private-demo`.
4. Keep anonymous access disabled.
5. Create the container.

### Assign access to the test VM identity

For an Entra ID-based test, assign an appropriate role such as **Storage Blob Data Contributor** to the VM's managed identity at the narrowest suitable scope, following your organization's policy.

If using Azure Bastion or a VM with no public IP, make sure the VM's identity and authentication setup are ready before testing.

---

## 7. Create the Blob Private Endpoint

1. Search **Private endpoints** → **Create**.
2. Basics:
   - Resource group: `rg-private-endpoint-demo`
   - Name: `pe-blob-demo`
   - Region: Central India
3. Resource:
   - Connection method: connect to an Azure resource in your directory
   - Resource type: `Microsoft.Storage/storageAccounts`
   - Select the Storage Account you created
   - Target sub-resource: **blob**
4. Virtual Network:
   - VNet: `vnet-private-endpoint-demo`
   - Subnet: `snet-private-endpoints`
5. DNS:
   - Enable integration with a private DNS zone.
   - Select/create `privatelink.blob.core.windows.net`.
   - Ensure the zone is linked to `vnet-private-endpoint-demo`.
6. Review + create → Create.
7. Wait until the Private Endpoint shows provisioning state **Succeeded** and connection state **Approved**.

### Record the private IP

1. Open `pe-blob-demo`.
2. Open **Network interface**.
3. Select its IP configuration.
4. Record the assigned private IP, for example `10.60.2.4`.

Use the actual IP from your environment; the example is not a guaranteed address.

---

## 8. Verify Private DNS

Open the private DNS zone `privatelink.blob.core.windows.net`:

1. Select **Virtual network links**.
2. Confirm the link to `vnet-private-endpoint-demo`.
3. Select **Record sets**.
4. Confirm the Storage Account's record exists and points to the Private Endpoint IP.

Use the normal service hostname in client tools:

```text
<storage-account>.blob.core.windows.net
```

Do not hard-code the Private Endpoint IP in applications. The normal hostname and private DNS preserve the expected TLS hostname and allow the DNS configuration to manage the address.

---

## 9. Create the client VM

1. Search **Virtual machines** → **Create**.
2. Resource group: `rg-private-endpoint-demo`.
3. Name: `vm-pe-client`.
4. Region: Central India.
5. Image: Ubuntu Server 24.04 LTS or an approved Ubuntu image.
6. Select an appropriate small lab size.
7. Configure SSH or other authentication according to your security policy.
8. Networking:
   - VNet: `vnet-private-endpoint-demo`
   - Subnet: `snet-client`
   - Public IP: **None preferred**
9. Create the VM.
10. Connect using Azure Bastion or another approved private administration method.

A public IP on the client VM is not required for the Private Endpoint data path. If the VM needs package downloads, provide approved outbound connectivity rather than opening broad inbound rules.

---

## 10. Prove private DNS and TCP connectivity

Run these commands on `vm-pe-client`.

Set the actual Storage Account name:

```bash
STORAGE_ACCOUNT="stpedemo<unique>"
```

### 10.1 Resolve the normal Blob hostname

```bash
getent hosts "${STORAGE_ACCOUNT}.blob.core.windows.net"
```

Optional:

```bash
nslookup "${STORAGE_ACCOUNT}.blob.core.windows.net"
```

Expected: the hostname chain resolves to the Private Endpoint's private IP, such as `10.60.2.4`, using the linked private DNS zone.

If the VM uses custom DNS, ensure that the custom resolver forwards or otherwise resolves the Azure Private DNS zone correctly.

### 10.2 Inspect the HTTPS response

```bash
curl -I --connect-timeout 5 "https://${STORAGE_ACCOUNT}.blob.core.windows.net/"
```

An HTTP response such as `400`, `403`, or another Storage service response can still show that HTTPS reached the service; unauthenticated requests are not expected to read private blob data. The network proof comes from the private DNS resolution plus the connection to the service. Continue with an authenticated blob operation for a full end-to-end proof.

---

## 11. Prove an authenticated Blob operation

### Recommended method: Microsoft Entra ID and Azure CLI

Install Azure CLI using an approved installation method if it is not already available. Authenticate using an approved identity method. For a VM with a managed identity, enable the identity on the VM and grant the required Storage data role.

Example commands:

```bash
az login --identity
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name private-demo \
  --auth-mode login
```

To upload a test file:

```bash
echo "Private Endpoint connectivity proof" > proof.txt

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name private-demo \
  --name proof.txt \
  --file proof.txt \
  --auth-mode login
```

To download and verify:

```bash
az storage blob download \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name private-demo \
  --name proof.txt \
  --file proof-downloaded.txt \
  --auth-mode login

cat proof-downloaded.txt
```

Expected output:

```text
Private Endpoint connectivity proof
```

The exact CLI messages may vary. Successful upload/download plus private DNS resolution and a disabled public endpoint provide strong end-to-end evidence.

**Authentication note:** `az login --identity` works only if the VM has a managed identity enabled and the identity has the necessary Storage data-plane RBAC permissions. If using another approved authentication method, follow your organization's policy. Avoid putting account keys or SAS tokens in shell history or README files.

---

## 12. Disable public network access and retest

For the strongest private-only demonstration, test connectivity first, then restrict public access.

1. Open the Storage Account → **Networking**.
2. Under **Public network access**, select **Disabled** (portal labels can change).
3. Save the change.
4. From `vm-pe-client`, repeat DNS resolution and the authenticated upload/download tests.
5. Confirm they still succeed.

Do not disable public access until you have a working Private Endpoint and an approved way to administer the resources. If the operation fails afterwards, verify the endpoint approval, DNS zone link, firewall settings, identity permissions, and the Storage Account's networking settings.

A private endpoint does not bypass Storage authorization. The identity must still have permission to read or write the blob.

---

## 13. Evidence checklist

Capture screenshots or terminal output from your actual deployment:

- [ ] Resource group inventory.
- [ ] VNet address space and subnet configuration.
- [ ] Storage Account Overview and Blob endpoint.
- [ ] Private Endpoint Overview showing provisioning state **Succeeded** and connection state **Approved**.
- [ ] Private Endpoint NIC showing its private IP.
- [ ] Private DNS zone and VNet link.
- [ ] DNS lookup showing the Blob hostname resolves to the private IP.
- [ ] Successful authenticated `az storage blob upload`.
- [ ] Successful download and displayed file content.
- [ ] Storage Account Networking page showing public network access disabled.
- [ ] Repeated upload/download after public access is disabled.

Redact subscription IDs, tenant IDs, public IPs, account keys, SAS tokens, passwords, and other sensitive information.

## 14. What proves Private Endpoint is being used?

| Claim | Evidence |
|---|---|
| Private Endpoint exists | Portal resource `pe-blob-demo` |
| Endpoint is connected | Provisioning succeeded and connection approved |
| Endpoint has a VNet private IP | Private Endpoint NIC IP configuration |
| DNS directs clients privately | Blob FQDN resolves to the endpoint private IP from the client VM |
| Private data operations work | Authenticated blob upload and download succeed |
| Public access is not required | Same operations succeed after Storage public network access is disabled |

No single screenshot proves everything. Collect configuration and runtime evidence together.

---

## 15. Troubleshooting

### DNS resolves to a public address

- Verify the Private DNS zone is `privatelink.blob.core.windows.net`.
- Confirm the zone has a VNet link to `vnet-private-endpoint-demo`.
- Check the record points to the Private Endpoint IP.
- Check the VM's DNS server and custom DNS forwarding.
- Flush or wait for DNS caches after changes.

### Private Endpoint is pending

- Open the Storage Account → **Networking / Private endpoint connections**.
- Approve the connection if manual approval is required.
- Confirm the endpoint targets the correct Storage Account and the `blob` sub-resource.

### DNS is private but blob operations fail

- Check the VM's identity and Storage Blob Data Contributor or other required role assignment.
- Confirm the container name and blob name.
- Verify Storage firewall/network settings and endpoint status.
- Check that you are using `--auth-mode login` with a valid authenticated identity.
- Remember: private networking does not grant data access by itself.

### HTTPS fails or times out

- Confirm DNS resolves to the endpoint IP.
- Confirm the Private Endpoint is approved and provisioned.
- Check NSGs, routes, and firewall policy.
- Verify outbound TCP 443 is allowed from the client VM.
- Do not test by using the endpoint IP directly in the URL because that can break expected hostname and TLS behavior.

### Upload worked before public access was disabled, but fails afterwards

- Check the Private Endpoint connection state and DNS zone link.
- Confirm the client is still resolving the normal Blob hostname to the private IP.
- Confirm the request originates from the intended VNet path.
- Verify the identity still has the required data-plane RBAC role.
- Check Storage network configuration and any organizational policy or firewall changes.

---

## 16. Production-readiness checklist

- [ ] Use private DNS zones and links with clear ownership.
- [ ] Disable public network access when the security design requires private-only access.
- [ ] Use Microsoft Entra ID and least-privilege Storage data roles where possible.
- [ ] Avoid account keys and long-lived SAS tokens where a stronger identity method is available.
- [ ] Review NSGs, routes, DNS forwarding, and egress controls.
- [ ] Monitor Private Endpoint connection state and relevant Storage diagnostics.
- [ ] Document endpoint approval and revocation procedures.
- [ ] Validate private access from each required VNet and connected network.
- [ ] Test failover, DNS, backup, and recovery requirements.
- [ ] Review service limits, regional support, and cost.
- [ ] Delete the lab after capturing evidence.

---

## 17. Cleanup

1. Save your evidence pack.
2. Open **Resource groups** → `rg-private-endpoint-demo`.
3. Select **Delete resource group**.
4. Type the resource group name and confirm.

Only delete the dedicated lab resource group if it contains no shared resources. If you reused shared VNets, DNS zones, or other resources, delete only the resources created for the lab.

---

## 18. Official Microsoft documentation

- [What is Azure Private Endpoint?](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Create a private endpoint — Azure portal](https://learn.microsoft.com/en-us/azure/private-link/create-private-endpoint-portal)
- [Azure Private Endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Use a private endpoint for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)

Verify current portal labels, supported regions, DNS behavior, service limits, and network policy requirements before deployment.

---

## 19. Lab completion record

- Resource group: `rg-private-endpoint-demo`
- Region: `Central India`
- VNet: `vnet-private-endpoint-demo`
- Storage Account: `________________`
- Private Endpoint: `pe-blob-demo`
- Endpoint private IP: `________________`
- Connection state: `________________`
- Private DNS zone linked: `Yes / No`
- Blob FQDN resolves privately: `Yes / No`
- Authenticated upload/download succeeded: `Yes / No`
- Public network access disabled: `Yes / No`
- Evidence folder/location: `________________`

### Pass condition

The Blob Private Endpoint is approved and provisioned, the normal Storage Blob hostname resolves to its private IP from the client VNet, an authenticated blob upload/download succeeds, and the operation continues to work after public network access is disabled.

**Final teaching takeaway:** A Private Endpoint gives your VNet a private IP for a supported Azure service. Private DNS makes the service's normal hostname resolve to that private IP. Network reachability and service authorization are separate requirements, and both must be verified.
