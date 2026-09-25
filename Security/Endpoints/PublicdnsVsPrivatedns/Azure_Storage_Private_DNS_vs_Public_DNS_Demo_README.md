# Azure Storage Account: Private DNS vs Public DNS Demo

## Objective

This lab demonstrates the difference between:

1. **Azure Storage Account using the public endpoint**
2. **Azure Storage Account using a Private Endpoint + Private DNS Zone**

You will test DNS resolution and connectivity from an Azure VM.

---

# Architecture

```text
                         Azure
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  VNet: vnet-storage-demo                                    │
│                                                             │
│  ┌──────────────────┐                                       │
│  │ Subnet: vm-subnet│                                       │
│  │                  │                                       │
│  │  Linux VM        │                                       │
│  │  vm-storage-test │                                       │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           │ Public endpoint                                 │
│           ▼                                                 │
│  storageaccount.blob.core.windows.net                      │
│           │                                                 │
│           ▼                                                 │
│     Public Azure IP                                        │
│                                                             │
│           OR                                                │
│                                                             │
│           │ Private Endpoint                                │
│           ▼                                                 │
│  ┌────────────────────────┐                                 │
│  │ Private Endpoint       │                                 │
│  │ Private IP: 10.10.2.x  │                                 │
│  └────────────┬───────────┘                                 │
│               │                                             │
│               ▼                                             │
│  privatelink.blob.core.windows.net                          │
│               │                                             │
│               ▼                                             │
│  ┌──────────────────────────────┐                           │
│  │ Private DNS Zone             │                           │
│  │ privatelink.blob.core...     │                           │
│  │ A record -> Private IP       │                           │
│  └──────────────────────────────┘                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# 1. Important Concept

A **Storage Account endpoint** normally looks like:

```text
https://<storage-account-name>.blob.core.windows.net
```

When the Storage Account is accessed through a Private Endpoint, Azure uses a private IP address.

The DNS name remains:

```text
<storage-account-name>.blob.core.windows.net
```

but DNS resolution from the VNet is designed to eventually resolve through:

```text
<storage-account-name>.privatelink.blob.core.windows.net
```

to the private endpoint IP.

---

# 2. Public Endpoint vs Private Endpoint

| Feature | Public Endpoint | Private Endpoint |
|---|---|---|
| DNS | Public DNS | Private DNS integration |
| IP | Public Azure IP | Private VNet IP |
| Internet exposure | Endpoint is publicly addressable | Traffic can stay on private Azure networking |
| VNet access | Not required | Required |
| Private DNS Zone | Not required | Recommended |
| Typical DNS Zone | `blob.core.windows.net` | `privatelink.blob.core.windows.net` |
| Network path | Public endpoint | Private Link |
| Firewall | Storage firewall can restrict access | Can combine with storage firewall/private access controls |

---

# 3. Prerequisites

Install:

```powershell
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

Verify:

```powershell
az account show --output table
```

Required permissions:

- Resource Group creation
- VNet/Subnet creation
- VM creation
- Storage Account creation
- Private Endpoint creation
- Private DNS Zone creation

---

# 4. Lab Variables

Run this in **PowerShell**.

```powershell
$location = "centralindia"

$rg = "rg-storage-private-dns-demo"

$vnet = "vnet-storage-demo"
$vmSubnet = "vm-subnet"
$peSubnet = "private-endpoint-subnet"

$vm = "vm-storage-test"

$storage = "stprivatednsdemo$(Get-Random -Minimum 1000 -Maximum 9999)"

$dnsZone = "privatelink.blob.core.windows.net"

$adminUser = "azureuser"
$adminPassword = "ChangeMe@123456"
```

> Storage Account names must be globally unique, lowercase, and contain only numbers and lowercase letters.

---

# 5. Create Resource Group

```powershell
az group create `
  --name $rg `
  --location $location
```

Verify:

```powershell
az group show `
  --name $rg `
  --output table
```

---

# 6. Create VNet

Create the VNet:

```powershell
az network vnet create `
  --resource-group $rg `
  --name $vnet `
  --address-prefix 10.10.0.0/16 `
  --subnet-name $vmSubnet `
  --subnet-prefix 10.10.1.0/24
```

Create the Private Endpoint subnet:

```powershell
az network vnet subnet create `
  --resource-group $rg `
  --vnet-name $vnet `
  --name $peSubnet `
  --address-prefix 10.10.2.0/24
```

Check:

```powershell
az network vnet subnet list `
  --resource-group $rg `
  --vnet-name $vnet `
  --output table
```

---

# 7. Create Linux VM

```powershell
az vm create `
  --resource-group $rg `
  --name $vm `
  --image Ubuntu2204 `
  --size Standard_B2s `
  --admin-username $adminUser `
  --admin-password $adminPassword `
  --authentication-type password `
  --vnet-name $vnet `
  --subnet $vmSubnet `
  --public-ip-sku Standard
```

Get the VM public IP:

```powershell
az vm show `
  --resource-group $rg `
  --name $vm `
  --show-details `
  --query publicIps `
  --output tsv
```

SSH:

```bash
ssh azureuser@<VM_PUBLIC_IP>
```

---

# 8. Create Storage Account

Create the Storage Account:

```powershell
az storage account create `
  --resource-group $rg `
  --name $storage `
  --location $location `
  --sku Standard_LRS `
  --kind StorageV2
```

Check:

```powershell
az storage account show `
  --resource-group $rg `
  --name $storage `
  --query "{name:name,publicNetworkAccess:publicNetworkAccess,defaultAction:networkRuleSet.defaultAction}" `
  --output table
```

---

# 9. Public DNS Demo

From the Linux VM:

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

or:

```bash
dig <STORAGE_ACCOUNT>.blob.core.windows.net
```

Example:

```bash
nslookup stprivatednsdemo1234.blob.core.windows.net
```

You should see a public Azure address.

Test HTTPS:

```bash
curl -I https://<STORAGE_ACCOUNT>.blob.core.windows.net
```

You may receive:

```text
HTTP/1.1 400 Bad Request
```

That is not necessarily a failure.

The important point is that the DNS name resolves and the request reaches the Storage service.

---

# 10. Check Public DNS Resolution

Run:

```bash
dig +short <STORAGE_ACCOUNT>.blob.core.windows.net
```

Also check the complete DNS chain:

```bash
dig <STORAGE_ACCOUNT>.blob.core.windows.net
```

The public endpoint can resolve through Azure's public DNS infrastructure.

---

# 11. Create Private Endpoint

First obtain the Storage Account resource ID:

```powershell
$storageId = az storage account show `
  --resource-group $rg `
  --name $storage `
  --query id `
  --output tsv
```

Create the Private Endpoint:

```powershell
az network private-endpoint create `
  --resource-group $rg `
  --name pe-storage-blob `
  --vnet-name $vnet `
  --subnet $peSubnet `
  --private-connection-resource-id $storageId `
  --group-id blob `
  --connection-name storage-blob-connection
```

Check:

```powershell
az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --output table
```

---

# 12. Get Private Endpoint IP

```powershell
az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --query "customDnsConfigs[].ipAddresses[]" `
  --output tsv
```

Example:

```text
10.10.2.4
```

This is the private IP assigned to the Storage Private Endpoint.

---

# 13. Create Private DNS Zone

Create:

```powershell
az network private-dns zone create `
  --resource-group $rg `
  --name $dnsZone
```

Check:

```powershell
az network private-dns zone show `
  --resource-group $rg `
  --name $dnsZone
```

---

# 14. Link Private DNS Zone to VNet

```powershell
az network private-dns link vnet create `
  --resource-group $rg `
  --zone-name $dnsZone `
  --name storage-vnet-link `
  --virtual-network $vnet `
  --registration-enabled false
```

Check:

```powershell
az network private-dns link vnet list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

---

# 15. Create Private DNS A Record

Get the Private Endpoint IP:

```powershell
$privateIp = az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --query "customDnsConfigs[0].ipAddresses[0]" `
  --output tsv
```

Create the A record:

```powershell
az network private-dns record-set a create `
  --resource-group $rg `
  --zone-name $dnsZone `
  --name $storage
```

Add the private IP:

```powershell
az network private-dns record-set a add-record `
  --resource-group $rg `
  --zone-name $dnsZone `
  --record-set-name $storage `
  --ipv4-address $privateIp
```

Verify:

```powershell
az network private-dns record-set a show `
  --resource-group $rg `
  --zone-name $dnsZone `
  --name $storage `
  --output json
```

---

# 16. DNS Resolution After Private Endpoint

From the VM:

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

or:

```bash
dig <STORAGE_ACCOUNT>.blob.core.windows.net
```

You should now see a private address such as:

```text
10.10.2.4
```

The important concept is:

```text
Application
    |
    | https://storage.blob.core.windows.net
    |
    v
Azure DNS
    |
    v
Private DNS resolution
    |
    v
10.10.2.4
    |
    v
Private Endpoint
    |
    v
Azure Storage
```

---

# 17. Compare DNS

## Before Private Endpoint

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

Conceptually:

```text
Storage DNS name
       |
       v
Public Azure endpoint
       |
       v
Public IP
```

## After Private Endpoint + Private DNS

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

Conceptually:

```text
Storage DNS name
       |
       v
Private DNS
       |
       v
10.10.2.x
       |
       v
Private Endpoint
       |
       v
Storage Account
```

---

# 18. Important DNS Architecture

There are two important DNS names.

### Normal Storage endpoint

```text
<storage>.blob.core.windows.net
```

### Private Link DNS zone

```text
privatelink.blob.core.windows.net
```

The Private DNS zone contains:

```text
<storage>.privatelink.blob.core.windows.net
        |
        v
    10.10.2.4
```

Azure Private Link DNS integration allows applications to continue using:

```text
<storage>.blob.core.windows.net
```

while DNS resolution inside the VNet can direct the connection to the Private Endpoint.

---

# 19. Check Private DNS Records

```powershell
az network private-dns record-set list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

Get the A record:

```powershell
az network private-dns record-set a list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

---

# 20. Test Private Connectivity

From the VM:

```bash
curl -I https://<STORAGE_ACCOUNT>.blob.core.windows.net
```

Check the route:

```bash
ip route
```

Check DNS:

```bash
cat /etc/resolv.conf
```

Check the resolved address:

```bash
getent hosts <STORAGE_ACCOUNT>.blob.core.windows.net
```

Check TCP 443:

```bash
nc -vz <STORAGE_ACCOUNT>.blob.core.windows.net 443
```

Expected:

```text
Connection to <STORAGE_ACCOUNT>.blob.core.windows.net 443 port [tcp/https] succeeded!
```

---

# 21. Stronger Demo: Disable Public Network Access

After confirming Private Endpoint connectivity, disable public network access:

```powershell
az storage account update `
  --resource-group $rg `
  --name $storage `
  --public-network-access Disabled
```

Check:

```powershell
az storage account show `
  --resource-group $rg `
  --name $storage `
  --query publicNetworkAccess
```

Expected:

```text
"Disabled"
```

Now test from the VM:

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

It should resolve to the private IP.

Test:

```bash
curl -I https://<STORAGE_ACCOUNT>.blob.core.windows.net
```

The request can continue to use the Private Endpoint.

---

# 22. Test From Outside the VNet

From your laptop or another machine that is not connected to the VNet:

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

The DNS result will not use the VNet's Private DNS resolution.

If public network access is disabled, direct access to the Storage Account through the public endpoint will not be available.

This demonstrates the purpose of Private Endpoint + Private DNS:

```text
Inside VNet
    |
    v
Private DNS
    |
    v
Private IP
    |
    v
Private Endpoint
    |
    v
Storage


Outside VNet
    |
    v
Public DNS / public endpoint
    |
    v
Public access blocked
```

---

# 23. Storage Firewall vs Private Endpoint

These are different concepts.

## Storage Firewall

Controls access to the Storage Account's network endpoint.

Example:

```text
Allow selected networks
Allow public IP ranges
Allow Azure services
```

## Private Endpoint

Creates a private IP address inside your VNet.

```text
VNet
 |
 +-- Private Endpoint
        |
        +-- Private IP
```

## Private DNS

Makes DNS resolution point applications toward the private endpoint.

```text
storage.blob.core.windows.net
              |
              v
       Private DNS
              |
              v
          10.10.2.4
```

---

# 24. Very Important: Private DNS Does Not Create the Private Endpoint

Creating only:

```text
Private DNS Zone
```

does NOT make Storage private.

You need:

```text
Storage Account
       +
Private Endpoint
       +
Private DNS Zone
       +
VNet DNS integration
```

The relationship is:

```text
Storage Account
      |
      | Private Link
      v
Private Endpoint
      |
      | private IP
      v
VNet
      |
      | DNS resolution
      v
Private DNS Zone
```

---

# 25. Azure CLI Verification Commands

## Storage Account

```powershell
az storage account show `
  --resource-group $rg `
  --name $storage `
  --output json
```

## Private Endpoint

```powershell
az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --output json
```

## Private DNS Zone

```powershell
az network private-dns zone show `
  --resource-group $rg `
  --name $dnsZone `
  --output json
```

## DNS VNet Link

```powershell
az network private-dns link vnet list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

## Private DNS A Record

```powershell
az network private-dns record-set a list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

---

# 26. Useful Troubleshooting Commands

From Linux VM:

```bash
nslookup <STORAGE_ACCOUNT>.blob.core.windows.net
```

```bash
dig <STORAGE_ACCOUNT>.blob.core.windows.net
```

```bash
getent hosts <STORAGE_ACCOUNT>.blob.core.windows.net
```

```bash
curl -v https://<STORAGE_ACCOUNT>.blob.core.windows.net
```

```bash
nc -vz <STORAGE_ACCOUNT>.blob.core.windows.net 443
```

Check DNS configuration:

```bash
resolvectl status
```

Check Azure VM NIC:

```powershell
az vm show `
  --resource-group $rg `
  --name $vm `
  --show-details `
  --query networkProfile.networkInterfaces
```

---

# 27. Common Problems

## Problem 1: DNS returns public IP

Check:

```powershell
az network private-dns link vnet list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

Make sure the VNet is linked.

---

## Problem 2: Private DNS record missing

Check:

```powershell
az network private-dns record-set a list `
  --resource-group $rg `
  --zone-name $dnsZone `
  --output table
```

Create the record if required.

---

## Problem 3: Private Endpoint exists but connection fails

Check the NIC:

```powershell
az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --query networkInterfaces
```

Check the private IP:

```powershell
az network private-endpoint show `
  --resource-group $rg `
  --name pe-storage-blob `
  --query "customDnsConfigs[].ipAddresses[]"
```

---

## Problem 4: DNS works but HTTPS fails

Check:

```bash
nc -vz <STORAGE_ACCOUNT>.blob.core.windows.net 443
```

Check NSG rules on the subnet.

Check:

- Private Endpoint connection status
- Storage Account network configuration
- DNS resolution
- Route table
- NSG
- Azure Firewall if present

---

# 28. Automatic Private DNS Integration

Azure CLI can also create the Private DNS Zone Group when creating the Private Endpoint.

Example:

```powershell
az network private-endpoint dns-zone-group create `
  --resource-group $rg `
  --endpoint-name pe-storage-blob `
  --name default `
  --private-dns-zone $dnsZone `
  --zone-name blob
```

Check:

```powershell
az network private-endpoint dns-zone-group show `
  --resource-group $rg `
  --endpoint-name pe-storage-blob `
  --name default
```

This approach is generally preferable to manually maintaining the A record because Azure manages the Private Endpoint DNS integration.

---

# 29. Recommended Production Pattern

For production:

```text
                         Azure VNet
                            |
                 ┌──────────┴──────────┐
                 |                     |
             Application             DNS
                 |                     |
                 |              Azure Private DNS
                 |                     |
                 |       privatelink.blob.core.windows.net
                 |                     |
                 |                     v
                 |              Private Endpoint
                 |                     |
                 └─────────────────────┘
                                       |
                                       v
                               Azure Storage Account
```

For multiple VNets:

```text
                 Hub VNet
                    |
          Azure Private DNS Zone
                    |
        ┌───────────┼───────────┐
        |           |           |
     Spoke 1     Spoke 2     Spoke 3
        |           |           |
       VM          VM          VM
        \           |           /
         \          |          /
          Private Endpoint(s)
                 |
                 v
            Azure Storage
```

---

# 30. Cleanup

Delete the complete resource group:

```powershell
az group delete `
  --name $rg `
  --yes `
  --no-wait
```

Verify:

```powershell
az group exists `
  --name $rg
```

Expected:

```text
false
```

---

# 31. Teaching Summary

Use this simple explanation during the demo:

### Public DNS

```text
VM
 |
 | DNS
 v
storage.blob.core.windows.net
 |
 v
Public Azure IP
 |
 v
Storage
```

### Private DNS + Private Endpoint

```text
VM
 |
 | DNS
 v
storage.blob.core.windows.net
 |
 v
Private DNS
 |
 v
10.10.2.4
 |
 v
Private Endpoint
 |
 v
Storage
```

### Key takeaway

```text
Private Endpoint = Private network connectivity

Private DNS = Correct private DNS resolution

Storage Firewall = Network access control
```

They solve different parts of the problem and are commonly used together.

---

# 32. Demo Checklist

```text
[ ] Create Resource Group
[ ] Create VNet
[ ] Create VM subnet
[ ] Create Private Endpoint subnet
[ ] Create Linux VM
[ ] Create Storage Account
[ ] Test public DNS
[ ] Test public Storage endpoint
[ ] Create Private Endpoint
[ ] Get Private Endpoint private IP
[ ] Create Private DNS Zone
[ ] Link DNS Zone to VNet
[ ] Create/verify DNS record
[ ] Test DNS from VM
[ ] Test HTTPS from VM
[ ] Disable public network access
[ ] Test private connectivity
[ ] Test access from outside VNet
[ ] Delete resources
```

---

# Final Concept

The most important distinction is:

```text
                 DNS                         Network
                  |                            |
                  v                            v

Private DNS  -------------------->  Private Endpoint
      |                                   |
      | resolves name                    | provides
      | to private IP                    | private IP
      v                                   v
10.10.2.4  --------------------------> Storage
```

**Private DNS does not make a Storage Account private by itself.**

**Private Endpoint provides the private connectivity.**

**Private DNS makes the normal Storage FQDN resolve to that private connectivity from the VNet.**
