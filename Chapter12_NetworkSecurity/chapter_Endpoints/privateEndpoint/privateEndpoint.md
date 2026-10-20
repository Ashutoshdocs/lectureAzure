# Azure Private Endpoint Demo — Without Private Link Service

## 🎯 Objective

This practical demonstrates an Azure **Private Endpoint** without creating or using an Azure **Private Link Service**.

We will use:

- Azure VNet
- Azure VM
- Azure Storage Account
- Storage Account Blob Private Endpoint
- Private DNS Zone
- Azure VM to Storage communication

The goal is to prove:

```text
Azure VM
   |
   | Private VNet
   v
Private Endpoint
   |
   v
Azure Storage Account
```

There will be:

```text
❌ No Private Link Service
❌ No public Storage access required
❌ No VNet Integration
❌ No VNet Injection
```

---

# 1. What Are We Demonstrating?

A **Private Endpoint** creates a network interface with a **private IP address inside your VNet**.

That private IP represents the Azure PaaS resource from inside the VNet.

For this demo:

```text
Storage Account
       |
       |
Private Endpoint
       |
       v
10.30.2.x
       |
       |
      VNet
       |
       v
Azure VM
```

The Azure VM will access the Storage Account using the Storage Account's normal DNS name, but DNS will resolve that name to the **Private Endpoint IP**.

---

# 2. Important: Private Endpoint Does NOT Mean Private Link Service

This distinction is critical.

## Private Endpoint

```text
Your VNet
   |
   v
Private Endpoint
   |
   v
Azure PaaS Service
```

Example:

```text
VM
 |
 v
Private Endpoint
 |
 v
Azure Storage Account
```

You do **not** create a Private Link Service for this scenario.

---

## Private Link Service

Private Link Service is used when **you own the service/backend** and want to publish it privately to consumers through Azure Private Link.

Conceptually:

```text
Consumer VNet
      |
      v
Private Endpoint
      |
      v
Private Link Service
      |
      v
Your Load Balancer
      |
      v
Your backend
```

That is NOT what we are building here.

---

# 3. Final Architecture

```text
                         AZURE
┌─────────────────────────────────────────────────────┐
│                                                     │
│                 VNet 10.30.0.0/16                  │
│                                                     │
│  VM Subnet                         PE Subnet        │
│  10.30.1.0/24                      10.30.2.0/24    │
│                                                     │
│  ┌──────────────┐                  ┌─────────────┐  │
│  │ Azure VM     │                  │ Private     │  │
│  │              │                  │ Endpoint    │  │
│  │ 10.30.1.x    │─────────────────▶│ 10.30.2.x   │  │
│  └──────────────┘                  └──────┬──────┘  │
│                                           │         │
│                                           │         │
└───────────────────────────────────────────|─────────┘
                                            |
                                            |
                                    Azure Private Link
                                            |
                                            v
                                  ┌──────────────────┐
                                  │ Storage Account  │
                                  │ Blob Service     │
                                  └──────────────────┘


                    Private Link Service
                           ❌
                         NOT USED
```

---

# 4. How the Traffic Works

When the VM executes:

```bash
nslookup mystorage.blob.core.windows.net
```

the DNS response should point the storage hostname to the Private Endpoint's private IP through the private DNS configuration.

Conceptually:

```text
mystorage.blob.core.windows.net
              |
              v
      Private DNS Zone
              |
              v
         10.30.2.4
              |
              v
      Private Endpoint
              |
              v
      Storage Account
```

The application does not need to know:

```text
10.30.2.4
```

It can continue using:

```text
https://mystorage.blob.core.windows.net
```

DNS determines the private destination.

---

# 5. Prerequisites

You need:

- Azure subscription
- Azure CLI
- PowerShell
- Permission to create networking resources
- Azure VM
- Azure Storage Account

---

# 6. Set Variables

Run in PowerShell:

```powershell
$LOCATION="centralindia"
$RG="PrivateEndpointDemoRG"

$VNET="vnet-private-endpoint-demo"

$VM_SUBNET="vm-subnet"
$PE_SUBNET="private-endpoint-subnet"

$VM="private-endpoint-client-vm"

$STORAGE="pe$(Get-Random -Minimum 100000 -Maximum 999999)"
```

Storage account names must be globally unique and use only lowercase letters and numbers.

---

# 7. Create Resource Group

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

# 8. Create VNet

```powershell
az network vnet create `
  --resource-group $RG `
  --name $VNET `
  --location $LOCATION `
  --address-prefix 10.30.0.0/16
```

---

# 9. Create VM Subnet

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $VM_SUBNET `
  --address-prefix 10.30.1.0/24
```

---

# 10. Create Private Endpoint Subnet

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name $PE_SUBNET `
  --address-prefix 10.30.2.0/24
```

For a clean demonstration, use a dedicated subnet for Private Endpoints.

---

# 11. Create Azure VM

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

Example:

```text
10.30.1.4
```

---

# 12. Create Storage Account

```powershell
az storage account create `
  --resource-group $RG `
  --name $STORAGE `
  --location $LOCATION `
  --sku Standard_LRS `
  --kind StorageV2 `
  --public-network-access Disabled
```

Important:

```text
--public-network-access Disabled
```

This makes the demonstration stronger because the Storage Account is not being accessed through its public network endpoint.

---

# 13. Create Storage Container

Get the Storage Account key:

```powershell
$STORAGEKEY=$(az storage account keys list `
  --resource-group $RG `
  --account-name $STORAGE `
  --query "[0].value" `
  -o tsv)
```

Create a container:

```powershell
az storage container create `
  --account-name $STORAGE `
  --name demo `
  --account-key $STORAGEKEY
```

Expected:

```text
{
  "created": true
}
```

---

# 14. Create a Test File

Create a local file:

```powershell
"Private Endpoint Demo - Data stored in Azure Storage" | Out-File test.txt
```

Upload it:

```powershell
az storage blob upload `
  --account-name $STORAGE `
  --container-name demo `
  --name test.txt `
  --file test.txt `
  --account-key $STORAGEKEY
```

Verify:

```powershell
az storage blob list `
  --account-name $STORAGE `
  --container-name demo `
  --account-key $STORAGEKEY `
  -o table
```

---

# 15. Get Storage Resource ID

```powershell
$STORAGEID=$(az storage account show `
  --resource-group $RG `
  --name $STORAGE `
  --query id `
  -o tsv)
```

Display:

```powershell
$STORAGEID
```

---

# 16. Create Private Endpoint

Create a Private Endpoint for the Blob service:

```powershell
az network private-endpoint create `
  --resource-group $RG `
  --name storage-private-endpoint `
  --vnet-name $VNET `
  --subnet $PE_SUBNET `
  --private-connection-resource-id $STORAGEID `
  --group-id blob `
  --connection-name storage-private-connection
```

The important parameters are:

```text
--vnet-name $VNET
--subnet $PE_SUBNET
--private-connection-resource-id $STORAGEID
--group-id blob
```

---

# 17. ⭐ Get the Private Endpoint IP

```powershell
az network private-endpoint show `
  --resource-group $RG `
  --name storage-private-endpoint `
  --query customDnsConfigs `
  -o json
```

Example:

```json
[
  {
    "fqdn": "mystorage.blob.core.windows.net",
    "ipAddresses": [
      "10.30.2.4"
    ]
  }
]
```

The actual IP will be different in your environment.

Save it:

```powershell
$PEIP=$(az network private-endpoint show `
  --resource-group $RG `
  --name storage-private-endpoint `
  --query "customDnsConfigs[0].ipAddresses[0]" `
  -o tsv)

$PEIP
```

---

# 18. Create Private DNS Zone

Create the Azure Storage Blob private DNS zone:

```powershell
az network private-dns zone create `
  --resource-group $RG `
  --name "privatelink.blob.core.windows.net"
```

---

# 19. Link Private DNS Zone to VNet

```powershell
az network private-dns link vnet create `
  --resource-group $RG `
  --zone-name "privatelink.blob.core.windows.net" `
  --name storage-private-dns-link `
  --virtual-network $VNET `
  --registration-enabled false
```

---

# 20. Create DNS Zone Group

Associate the Private Endpoint with the Private DNS zone:

```powershell
az network private-endpoint dns-zone-group create `
  --resource-group $RG `
  --endpoint-name storage-private-endpoint `
  --name storage-dns-zone-group `
  --private-dns-zone "privatelink.blob.core.windows.net" `
  --zone-name blob
```

This creates the private DNS record needed for name resolution.

---

# 21. ⭐ PROOF #1 — Private Endpoint Exists

Run:

```powershell
az network private-endpoint list `
  --resource-group $RG `
  -o table
```

You should see:

```text
storage-private-endpoint
```

---

# 22. ⭐ PROOF #2 — Private Endpoint Has a Private IP

Run:

```powershell
az network private-endpoint show `
  --resource-group $RG `
  --name storage-private-endpoint `
  --query customDnsConfigs `
  -o json
```

Example:

```text
10.30.2.4
```

The address belongs to:

```text
VNet:             10.30.0.0/16
Private Endpoint: 10.30.2.0/24
Private IP:       10.30.2.4
```

Therefore:

```text
Storage Account
      |
      v
Private Endpoint
      |
      v
10.30.2.4
```

---

# 23. ⭐ PROOF #3 — DNS Resolves to Private IP

SSH into the VM:

```powershell
ssh azureuser@$VMPUBLICIP
```

Install DNS tools:

```bash
sudo apt update
sudo apt install dnsutils -y
```

Run:

```bash
nslookup <STORAGE>.blob.core.windows.net
```

Example:

```bash
nslookup mystorage.blob.core.windows.net
```

Expected:

```text
Name:    mystorage.blob.core.windows.net
Address: 10.30.2.4
```

The important result is:

```text
10.30.2.4
```

This is a private IP.

---

# 24. ⭐ PROOF #4 — Route to Private Endpoint

From the VM:

```bash
ip route get 10.30.2.4
```

Example:

```text
10.30.2.4 dev eth0 src 10.30.1.4
```

This shows the VM has a route through its VNet interface toward the Private Endpoint's private address.

---

# 25. ⭐ PROOF #5 — TCP Connectivity

Install netcat:

```bash
sudo apt install netcat-openbsd -y
```

Storage Blob HTTPS uses port 443.

Run:

```bash
nc -vz 10.30.2.4 443
```

Expected:

```text
Connection to 10.30.2.4 443 port [tcp/https] succeeded!
```

This proves network-level connectivity to the Private Endpoint.

---

# 26. ⭐ PROOF #6 — Access Storage Through Its Normal DNS Name

Install Azure CLI on the VM if necessary:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Login:

```bash
az login
```

List the blob:

```bash
az storage blob list `
  --account-name $STORAGE `
  --container-name demo `
  --auth-mode login `
  -o table
```

If using Bash on the VM:

```bash
az storage blob list \
  --account-name <STORAGE_ACCOUNT> \
  --container-name demo \
  --auth-mode login \
  -o table
```

The request uses the normal Storage endpoint name, while DNS resolves it through the private endpoint.

---

# 27. ⭐ Download the Blob From the VM

Run:

```bash
az storage blob download \
  --account-name <STORAGE_ACCOUNT> \
  --container-name demo \
  --name test.txt \
  --file downloaded.txt \
  --auth-mode login
```

Read it:

```bash
cat downloaded.txt
```

Expected:

```text
Private Endpoint Demo - Data stored in Azure Storage
```

This is the end-to-end data proof.

---

# 28. ⭐ Final End-to-End Flow

```text
                     AZURE VM
                  10.30.1.4
                      |
                      |
                DNS Request
                      |
                      v
     <storage>.blob.core.windows.net
                      |
                      v
          Private DNS Resolution
                      |
                      v
                  10.30.2.4
                      |
                      v
             PRIVATE ENDPOINT
                      |
                      |
               Azure Private Link
                      |
                      v
              STORAGE ACCOUNT
                      |
                      v
                Blob Container
                      |
                      v
                  test.txt
```

---

# 29. The Critical Difference

The VM is NOT connecting like this:

```text
VM
 |
 v
Internet
 |
 v
Public Storage Endpoint
```

Instead:

```text
VM
 |
 | Private IP
 v
Private Endpoint
 |
 v
Storage Account
```

---

# 30. ⭐ Prove Public Access Is Disabled

Run:

```powershell
az storage account show `
  --resource-group $RG `
  --name $STORAGE `
  --query "{Name:name,PublicNetworkAccess:publicNetworkAccess}" `
  -o json
```

Expected:

```json
{
  "Name": "pe123456",
  "PublicNetworkAccess": "Disabled"
}
```

This makes the demo very strong:

```text
Public access
     ❌ Disabled

Private Endpoint
     ✅ Enabled

VM → Storage
     ✅ Works
```

---

# 31. ⭐ Prove There Is NO Private Link Service

Run:

```powershell
az network private-link-service list `
  --resource-group $RG `
  -o table
```

Expected:

```text
No Private Link Services
```

This is exactly what we want.

The architecture is:

```text
VM
 |
 v
Private Endpoint
 |
 v
Azure Storage
```

NOT:

```text
VM
 |
 v
Private Endpoint
 |
 v
Private Link Service
 |
 v
Load Balancer
 |
 v
Backend
```

---

# 32. Private Endpoint vs Private Link Service

## Private Endpoint

Used to privately access a service:

```text
Consumer
  |
  v
Private Endpoint
  |
  v
Azure PaaS Service
```

Examples:

```text
Storage Account
SQL Database
Key Vault
Cosmos DB
Azure Database for PostgreSQL
```

---

## Private Link Service

Used when you expose **your own service** privately:

```text
Consumer
   |
   v
Private Endpoint
   |
   v
Private Link Service
   |
   v
Azure Load Balancer
   |
   v
Your application
```

Therefore:

> **You do not need Private Link Service just because you are using a Private Endpoint.**

---

# 33. Private Endpoint vs Public Endpoint

## Public Endpoint

```text
VM
 |
 v
Internet
 |
 v
Public Storage Endpoint
```

## Private Endpoint

```text
VM
 |
 v
VNet
 |
 v
Private Endpoint
 |
 v
Storage Account
```

The same service can conceptually be accessed using its service DNS name, but private DNS makes that name resolve to the private endpoint when queried from the VNet.

---

# 34. ⭐ Final Proof Checklist

Run these tests:

### Test 1 — Private Endpoint exists

```powershell
az network private-endpoint list -g $RG -o table
```

Expected:

```text
storage-private-endpoint
```

### Test 2 — Private IP

```powershell
az network private-endpoint show `
  -g $RG `
  -n storage-private-endpoint `
  --query customDnsConfigs
```

Expected:

```text
10.30.2.x
```

### Test 3 — DNS

From VM:

```bash
nslookup <STORAGE>.blob.core.windows.net
```

Expected:

```text
10.30.2.x
```

### Test 4 — Network

```bash
nc -vz 10.30.2.x 443
```

Expected:

```text
succeeded
```

### Test 5 — Data

```bash
az storage blob download \
  --account-name <STORAGE> \
  --container-name demo \
  --name test.txt \
  --file downloaded.txt \
  --auth-mode login
```

Then:

```bash
cat downloaded.txt
```

Expected:

```text
Private Endpoint Demo - Data stored in Azure Storage
```

### Test 6 — Public access

```powershell
az storage account show `
  -g $RG `
  -n $STORAGE `
  --query publicNetworkAccess
```

Expected:

```text
Disabled
```

### Test 7 — Private Link Service

```powershell
az network private-link-service list `
  -g $RG `
  -o table
```

Expected:

```text
No Private Link Service
```

---

# 35. 🎓 One-Line Teaching Definition

> **Private Endpoint = a private network interface with a private IP in your VNet that provides private access to a supported Azure service.**

And:

> **Private Endpoint does NOT require a Private Link Service when connecting to Azure-managed PaaS services such as Storage.**

---

# 36. Final Architecture to Remember

```text
              YOUR VNET
┌─────────────────────────────────────┐
│                                     │
│  Azure VM                           │
│  10.30.1.4                          │
│       │                             │
│       │ HTTPS 443                   │
│       ▼                             │
│  Private Endpoint                   │
│  10.30.2.4                          │
│       │                             │
└───────|─────────────────────────────┘
        |
        | Azure Private Link
        |
        ▼
┌──────────────────────────┐
│ Azure Storage Account    │
│                          │
│ Blob: test.txt           │
└──────────────────────────┘

Private Link Service: ❌
Private Endpoint:     ✅
Private DNS:           ✅
Public Storage Access: ❌
```

---

# 37. Cleanup

When the practical is finished:

```powershell
az group delete `
  --name $RG `
  --yes `
  --no-wait
```

This removes:

- Azure VM
- Storage Account
- Private Endpoint
- Private DNS Zone
- VNet
- Subnets
- Public IP
- NIC
- Other resources in the resource group

---

# 🎓 Final Teaching Statement

> **In this demo, the Azure VM accesses an Azure Storage Account through a Private Endpoint. The Private Endpoint has a private IP address inside the VNet, DNS resolves the Storage hostname to that private address, public Storage access is disabled, and no Private Link Service is involved.**
