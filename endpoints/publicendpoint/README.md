# Azure Public Endpoint — End-to-End Teaching Demo

> **Goal:** Teach and prove how an Azure Storage Account can be accessed through its **public service endpoint**, using the normal Blob Storage FQDN over HTTPS.
>
> **Scope:** This lab demonstrates public endpoint connectivity for Azure Blob Storage. It does not use a Private Endpoint, Private Link Service, App Service VNet Integration, or VNet injection.

This is a teaching lab, not a claim that resources have already been deployed. Capture evidence from your actual Azure subscription. For production, expose only the services and networks required by your security design; public endpoint does not mean anonymous access.

---

## 1. Learning outcomes

By completing this demo, you will learn to:

1. Explain an Azure public endpoint.
2. Create a Storage Account and Blob container.
3. Verify the public Blob service hostname resolves to public service IPs.
4. Upload and download a blob over HTTPS.
5. Configure Storage networking to allow selected public client IPs.
6. Understand the difference between public network reachability and data authorization.
7. Compare public endpoint connectivity with Private Endpoint connectivity.
8. Capture portal and command-line evidence for the practical.

## 2. What is a public endpoint?

A public endpoint is a service endpoint reachable through a service's publicly addressable hostname and Azure's public service network. For Blob Storage, the usual hostname is:

```text
https://<storage-account>.blob.core.windows.net/
```

A public endpoint can be restricted using Storage networking controls. A public endpoint does **not** automatically mean:

- anonymous access is enabled;
- every internet client is allowed;
- the storage account's data is publicly readable;
- traffic is unencrypted.

In this lab, clients connect to the normal Blob FQDN over HTTPS. Storage authorization is still required, and the network firewall is configured to allow only the test client's public IP where practical.

---

## 3. Architecture

```text
                 Test client / admin workstation
                 Azure CLI + authenticated identity
                              |
                              | HTTPS TCP 443
                              v
                  Public Blob service hostname
                  <account>.blob.core.windows.net
                              |
                              v
+---------------------------------------------------------------+
| Azure Storage public service endpoint                         |
|                                                               |
| Storage Account: stpublicdemo<unique>                         |
| Blob service                                                   |
| Network access: selected public networks (test client IP)     |
| Authentication: Microsoft Entra ID / RBAC                     |
+---------------------------------------------------------------+
```

### Request flow

1. The client resolves `<account>.blob.core.windows.net` using its normal DNS resolver.
2. The client connects to the public Blob service endpoint over HTTPS/TCP 443.
3. Azure Storage evaluates the account's network rules.
4. Azure Storage authenticates the request and checks data-plane permissions.
5. The upload/download succeeds if both network access and authorization are allowed.

**Two separate checks are involved:**
- **Network access:** Is this client allowed by the Storage Account's public network access and firewall settings?
- **Data authorization:** Does the authenticated identity have permission to read/write blobs?

A `403` response may indicate a network-rule or authorization issue; inspect the response details and configuration rather than assuming it proves the endpoint is unreachable.

---

## 4. Resource plan

Example region: **Central India**.

| Resource | Example name | Configuration |
|---|---|---|
| Resource group | `rg-public-endpoint-demo` | Central India |
| Storage Account | `stpublicdemo<unique>` | Standard, GPv2 |
| Blob container | `public-demo` | Private container; no anonymous access |
| Test client | Admin workstation or Azure VM | Azure CLI + approved identity |
| Endpoint | Blob service public endpoint | `<account>.blob.core.windows.net` |

Storage Account names must be globally unique, lowercase, and use supported characters.

### Prerequisites

- Azure subscription and permission to create a Storage Account and role assignments.
- Azure CLI on the client, or access to Azure Portal Cloud Shell.
- An authenticated Microsoft Entra identity.
- Permission to assign or receive a suitable Storage Blob data role.
- Budget awareness: the Storage Account and data operations may incur charges.

For the easiest test, use Azure Cloud Shell or an approved admin workstation. If you test from a VM, ensure its outbound HTTPS path is allowed. This demo does not require a VNet or VM unless your teaching scenario needs one.

---

## 5. Create the resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Select your subscription.
4. Name: `rg-public-endpoint-demo`.
5. Region: Central India.
6. Select **Review + create** → **Create**.

---

## 6. Create the Storage Account

1. Search **Storage accounts** → **Create**.
2. Basics:
   - Resource group: `rg-public-endpoint-demo`
   - Storage Account name: `stpublicdemo<unique>`
   - Region: Central India
   - Performance: Standard
   - Redundancy: choose an appropriate lab option
3. Keep secure transfer required (HTTPS) enabled.
4. Keep anonymous blob access disabled.
5. Review + create → Create.

After deployment, open the Storage Account → **Overview** and record the Blob service endpoint:

```text
https://<storage-account>.blob.core.windows.net/
```

### Create a Blob container

1. Open the Storage Account → **Data storage → Containers**.
2. Select **+ Container**.
3. Name: `public-demo`.
4. Anonymous access level: **Private (no anonymous access)**.
5. Create the container.

The container remains private even though the service is reached through a public endpoint.

---

## 7. Configure public network access

The portal may present different networking options depending on the Storage Account and current Azure experience.

1. Open the Storage Account → **Networking**.
2. Under **Public network access**, select the option that permits access from selected public networks, or the equivalent supported setting.
3. Add the public IPv4 address or CIDR of your test workstation if using selected networks.
4. Save the change.
5. If you use Azure Cloud Shell, remember that its outbound public IP may not be a stable address you control. For a predictable firewall demonstration, use an approved client with a known public egress IP or use a temporary lab policy consistent with your organization's controls.
6. Do not use “all networks” in production just to make a test pass.

To discover the public egress IP of an approved client, use your organization's approved network tooling. Avoid posting that IP publicly if it is sensitive.

### Important

The Storage Account's public endpoint remains the service hostname. The firewall setting decides which public source networks can reach the data plane. If public network access is disabled, this public endpoint path will not work even though the hostname exists.

---

## 8. Grant data access using Microsoft Entra ID

Use identity-based access rather than account keys wherever possible.

1. Open the Storage Account → **Access Control (IAM)**.
2. Select **Add role assignment**.
3. Choose **Storage Blob Data Contributor** for a test identity that must upload and download blobs.
4. Assign the role to the correct user, group, service principal, or managed identity.
5. Scope the role as narrowly as the lab and available Azure RBAC options permit.
6. Wait for the role assignment to propagate.

**Note:** Azure subscription Owner/Contributor permissions alone do not necessarily grant Blob data-plane access. A suitable Storage data role is required.

---

## 9. Test the public endpoint with Azure CLI

Run these commands in Azure Cloud Shell or on a client with Azure CLI installed and an approved identity.

### 9.1 Sign in and select the subscription

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

In Azure Cloud Shell, you may already be signed in. Confirm the correct subscription before proceeding.

### 9.2 Set the Storage Account name

Replace the placeholder with the actual name:

```bash
STORAGE_ACCOUNT="stpublicdemo<unique>"
```

### 9.3 Verify the public endpoint hostname

```bash
nslookup "${STORAGE_ACCOUNT}.blob.core.windows.net"
```

The result should resolve through the public DNS path to public service IP addresses. The exact IPs can change, so do not hard-code or rely on one fixed address.

Check the endpoint configured in Azure:

```bash
az storage account show \
  --resource-group rg-public-endpoint-demo \
  --name "$STORAGE_ACCOUNT" \
  --query "{name:name,publicNetworkAccess:publicNetworkAccess,primaryBlobEndpoint:primaryEndpoints.blob}" \
  --output table
```

Expected: the Blob endpoint is the standard public FQDN, and public network access is configured according to the selected-network test setup. The exact `publicNetworkAccess` field can be `Enabled` or another supported state depending on configuration; inspect the Networking blade as well.

### 9.4 Upload a test blob

Create a file:

```bash
echo "Azure public endpoint connectivity proof" > public-proof.txt
```

Upload using Microsoft Entra ID:

```bash
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name public-demo \
  --name public-proof.txt \
  --file public-proof.txt \
  --auth-mode login
```

### 9.5 Download and verify

```bash
az storage blob download \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name public-demo \
  --name public-proof.txt \
  --file public-proof-downloaded.txt \
  --auth-mode login

cat public-proof-downloaded.txt
```

Expected output:

```text
Azure public endpoint connectivity proof
```

If the upload/download succeeds from the approved public client, it proves the public endpoint path is reachable and the identity is authorized.

---

## 10. Prove that network restrictions matter

Perform this test only in a dedicated lab and restore the intended policy after the test.

1. Record the currently allowed public client IP/CIDR in Storage Account → **Networking**.
2. Remove the test client's IP from the allowed list, or temporarily use a separate test client that is not allowed.
3. Retry the authenticated blob operation.
4. The operation should fail due to the Storage Account network rules, though the precise error can vary.
5. Restore the approved client IP/CIDR.
6. Retry the upload/download; it should work again.

This demonstrates that **public endpoint** means the service has a public endpoint path, not that every source is permitted.

Avoid opening the account to all networks as a troubleshooting shortcut. If a policy change is required, keep it time-limited and documented.

---

## 11. Evidence checklist

Capture screenshots or terminal output from your actual environment:

- [ ] Resource group overview.
- [ ] Storage Account Overview showing the Blob service endpoint.
- [ ] Storage container `public-demo` showing private/anonymous access disabled.
- [ ] Storage Account Networking blade showing public network access and selected network rules.
- [ ] IAM role assignment for the test identity.
- [ ] DNS lookup of `<account>.blob.core.windows.net` from the test client.
- [ ] Azure CLI query showing the Blob endpoint.
- [ ] Successful authenticated upload.
- [ ] Successful download and file content.
- [ ] Failed request from a client not allowed by the network rules (optional controlled test).
- [ ] Successful request after restoring the allowed client network.

Redact subscription IDs, tenant IDs, public IPs if sensitive, access keys, SAS tokens, passwords, and other secrets before sharing.

---

## 12. What proves public endpoint connectivity?

| Claim | Evidence |
|---|---|
| Storage exposes its standard Blob hostname | Storage Account Overview and `primaryEndpoints.blob` |
| Client uses public DNS path | DNS lookup from a client without Private Endpoint DNS configuration |
| Client reaches the public service | HTTPS request receives a Storage response |
| Authorized data access works | Authenticated blob upload and download succeed |
| Network rules control reachability | Request fails from a disallowed public source and succeeds when the approved source is restored |
| Data is not anonymous | Container access is private and CLI uses identity authentication |

A DNS result alone is not enough. Combine endpoint configuration, authenticated data operations, and the network-rule test.

---

## 13. Troubleshooting

### `AuthorizationPermissionMismatch` or `403`

- Verify the identity is signed in to the correct tenant and subscription.
- Confirm the identity has `Storage Blob Data Contributor` or the appropriate data-plane role.
- Wait for RBAC propagation.
- Verify the container and blob names.
- Inspect Storage error details to distinguish network-rule denial from data authorization failure.

### Network-rule error or request fails from the client

- Confirm the client's actual public egress IP matches the allowed rule.
- Check the Storage Account's public network access setting.
- Check whether selected networks or a resource-specific firewall policy is active.
- Verify outbound TCP 443 is allowed.
- Do not assume a public DNS response means the firewall permits access.

### DNS lookup fails

- Verify the Storage Account name and endpoint.
- Check the client's DNS resolver and outbound connectivity.
- If the client previously used a Private Endpoint, check whether private DNS records or custom DNS are still affecting resolution.

### Upload fails but DNS works

- Check identity and Storage data-plane role.
- Confirm network rules permit the source.
- Confirm secure transfer settings and HTTPS.
- Do not use account keys or anonymous access as an automatic workaround.

---

## 14. Public Endpoint vs. Private Endpoint

| Topic | Public endpoint | Private Endpoint |
|---|---|---|
| Client destination | Public service hostname and public service path | Normal service hostname resolves to a private IP in the VNet |
| Network reachability | Controlled by public network access and firewall rules | Uses Azure Private Link from the Private Endpoint |
| Internet-originating clients | May be allowed if policy/network rules permit | Do not reach the private endpoint directly over the public internet |
| DNS | Public service resolution unless private DNS overrides it | Private DNS commonly maps the service hostname to the endpoint's private IP |
| Authorization | Still required | Still required |
| Best fit | Publicly reachable services with carefully scoped network controls | Private-only or private network access requirements |

A Storage Account can have a public endpoint and one or more Private Endpoints configured at the same time, depending on its networking settings. For a private-only design, disable public network access and verify all required clients use private connectivity.

---

## 15. Production security checklist

- [ ] Keep anonymous Blob access disabled unless explicitly required and approved.
- [ ] Prefer Microsoft Entra ID and least-privilege Storage data roles.
- [ ] Restrict public network access to approved networks where the public endpoint is needed.
- [ ] Disable public network access when private-only access is required.
- [ ] Require HTTPS.
- [ ] Avoid exposing account keys or SAS tokens in scripts, terminal logs, and Git.
- [ ] Monitor Storage diagnostics, authentication events, and network policy changes.
- [ ] Review firewall rules, access scope, and exception expiry.
- [ ] Document who can change network access settings and how to restore them.
- [ ] Review cost, service limits, and regional requirements.

---

## 16. Cleanup

1. Save the evidence pack.
2. Open **Resource groups** → `rg-public-endpoint-demo`.
3. Select **Delete resource group**.
4. Type the resource group name and confirm.

Only delete the dedicated lab resource group if it contains no shared resources. Remove only the lab resources if shared resources were reused.

---

## 17. Official Microsoft documentation

- [Azure Storage network security](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security)
- [Configure Azure Storage firewalls and virtual networks](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security)
- [Authorize access to blobs using Microsoft Entra ID](https://learn.microsoft.com/en-us/azure/storage/blobs/authorize-access-azure-active-directory)
- [Azure Storage public endpoints and Private Endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)

Verify current portal labels, supported network settings, role names, and service behavior before deployment.

---

## 18. Lab completion record

- Resource group: `rg-public-endpoint-demo`
- Region: `Central India`
- Storage Account: `________________`
- Blob endpoint: `________________`
- Public network access mode: `________________`
- Allowed client public IP/CIDR: `________________`
- Data role assigned: `________________`
- DNS lookup result: `________________`
- Blob upload succeeded: `Yes / No`
- Blob download succeeded: `Yes / No`
- Disallowed-client test failed as expected: `Yes / No`
- Evidence folder/location: `________________`

### Pass condition

The Storage Account's standard Blob FQDN is reachable through the public endpoint from an approved public client, authenticated upload/download operations succeed, and the configured network rules restrict access from unapproved clients.

**Final teaching takeaway:** A public endpoint is a publicly addressable service path, not a guarantee of open access. Azure Storage network rules control which clients can reach it, and Microsoft Entra ID/RBAC controls what an authenticated client may do.
