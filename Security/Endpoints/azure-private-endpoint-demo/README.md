# Azure Storage Account + VM + Private Endpoint Demo

## Objective

This demo shows how an Azure Virtual Machine can access an Azure Storage Account privately through an Azure Private Endpoint.

The demo is designed to make the following concepts visible:

1. Storage Account as a PaaS service
2. Public endpoint vs private endpoint
3. Private Endpoint
4. Private Link
5. Private IP assignment
6. Private DNS
7. VNet-based private connectivity
8. How traffic flows from a VM to the Storage Account
9. How public network access can be disabled after private connectivity is established
10. Why a Private Endpoint does not require the customer to deploy a Private Link Service

---

# 1. Architecture

```text
                         AZURE
┌───────────────────────────────────────────────────────────────────┐
│                                                                   │
│   Virtual Network                                                 │
│   ┌───────────────────────────────────────────────────────────┐   │
│   │                                                           │   │
│   │   VM Subnet                         Private Endpoint      │   │
│   │   ┌───────────────┐                 ┌───────────────┐     │   │
│   │   │               │                 │ Private IP    │     │   │
│   │   │      VM       │ ──────────────► │ 10.x.x.x      │     │   │
│   │   │               │                 │               │     │   │
│   │   └───────────────┘                 └───────┬───────┘     │   │
│   │                                             │             │   │
│   └─────────────────────────────────────────────┼─────────────┘   │
│                                                 │                 │
│                                                 │ Azure Private   │
│                                                 │ Link            │
│                                                 ▼                 │
│                                        ┌───────────────────┐      │
│                                        │ Azure Storage     │      │
│                                        │ Account           │      │
│                                        │ Blob Service      │      │
│                                        └───────────────────┘      │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

# 2. What is being demonstrated?

The Storage Account is an Azure PaaS service.

Normally, a storage account has a service endpoint such as:

```text
<storage-account-name>.blob.core.windows.net
```

Without a Private Endpoint, the storage service is accessed through its public service endpoint.

With a Private Endpoint:

```text
VM
 |
 | DNS resolves storage hostname
 | to private IP
 v
Private Endpoint
 |
 | Azure Private Link
 v
Storage Account
```

The important point is:

> The Private Endpoint is a network interface with a private IP address in your VNet.

The storage account itself does not become a VM or receive a normal NIC inside your subnet.

---

# 3. Components

## 3.1 Virtual Machine

The VM is used as the client.

The VM should be deployed inside the VNet.

The VM will be used to verify:

- DNS resolution
- Private IP resolution
- Storage connectivity
- Private connectivity after public access is disabled

---

## 3.2 Virtual Network

The VNet provides the private network in which the VM and Private Endpoint are placed.

Example:

```text
VNet
10.0.0.0/16
```

Example subnets:

```text
VM subnet
10.0.1.0/24

Private Endpoint subnet
10.0.2.0/24
```

The exact address ranges are not important as long as they do not overlap with other networks.

---

# 4. Storage Account

Create a Storage Account for the demonstration.

The Storage Account will provide a Blob service.

Example logical flow:

```text
VM
 |
 | HTTPS
 |
 v
Storage Blob endpoint
```

Initially, the storage account can be reachable through its public endpoint.

The purpose of the lab is to change this behavior so that the VM accesses it privately.

---

# 5. Private Endpoint

Create a Private Endpoint for the Storage Account.

Select:

```text
Target resource:
Storage Account

Sub-resource:
blob
```

The Private Endpoint is placed inside the VNet.

For example:

```text
Private Endpoint IP
10.0.2.4
```

This IP belongs to the Private Endpoint's network interface.

---

# 6. What happens when the Private Endpoint is created?

Azure creates a network interface for the Private Endpoint.

Conceptually:

```text
Private Endpoint
       |
       v
Network Interface
       |
       v
Private IP
10.0.2.4
```

The Private Endpoint connects this private IP to the selected Azure service through Azure Private Link.

The VM therefore has a private destination inside its VNet.

---

# 7. DNS is extremely important

The VM normally accesses the Storage Account using its DNS name.

For example:

```text
mystorageaccount.blob.core.windows.net
```

When Private Endpoint connectivity is configured correctly, DNS should resolve the storage hostname to a private IP.

Conceptually:

```text
mystorageaccount.blob.core.windows.net
                 |
                 v
        Private DNS resolution
                 |
                 v
             10.0.2.4
                 |
                 v
        Private Endpoint
                 |
                 v
        Azure Storage
```

This is one of the most important things to demonstrate.

---

# 8. Private DNS Zone

For Blob Storage, the commonly used Private DNS zone is:

```text
privatelink.blob.core.windows.net
```

A Private DNS Zone can be linked to the VNet.

The Private Endpoint creates/uses the appropriate private DNS record.

The result is that the VM can continue using the normal Storage Account hostname while DNS directs the connection toward the private endpoint.

The application does not normally need to be changed to use the Private Endpoint IP directly.

---

# 9. DNS Resolution Flow

The conceptual DNS flow is:

```text
VM
 |
 | asks DNS:
 | mystorageaccount.blob.core.windows.net
 v
DNS
 |
 | private endpoint DNS configuration
 v
Private IP
 |
 | 10.0.2.4
 v
Private Endpoint
 |
 v
Storage Account
```

This is preferable to hard-coding the private IP in applications.

---

# 10. Traffic Flow

The complete traffic flow is:

```text
┌──────────────┐
│      VM      │
│ 10.0.1.x     │
└──────┬───────┘
       │
       │ HTTPS
       ▼
┌──────────────────┐
│ Private Endpoint │
│ 10.0.2.4         │
└────────┬─────────┘
         │
         │ Azure Private Link
         ▼
┌──────────────────┐
│ Storage Account  │
│ Blob Service     │
└──────────────────┘
```

The key teaching point is:

> The VM is not communicating with the Storage Account through the Storage Account's public IP.

The VM connects to the Private Endpoint's private IP.

Azure then privately connects the Private Endpoint to the Storage service.

---

# 11. Public Endpoint vs Private Endpoint

## Public Endpoint

Conceptually:

```text
VM
 |
 | Internet/public endpoint
 v
Storage Account
```

The service is accessed through the public endpoint.

Network access controls can still restrict who can access it, but the endpoint itself is public.

---

## Private Endpoint

Conceptually:

```text
VM
 |
 | Private IP
 v
Private Endpoint
 |
 | Azure Private Link
 v
Storage Account
```

The VM uses a private IP destination.

---

# 12. Important distinction: Private Endpoint vs Private Link Service

These are different concepts.

## Private Endpoint

Used by a consumer to privately access a service.

Examples:

```text
Storage Account
Azure SQL
Key Vault
Cosmos DB
```

The consumer creates a Private Endpoint in its VNet.

---

## Private Link Service

Used by a service provider to expose its own service privately through Azure Private Link.

Typical architecture:

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
Provider Load Balancer
      |
      v
Provider Application
```

For this Storage Account demo:

```text
VM
 |
 v
Private Endpoint
 |
 v
Azure Storage
```

You do **not** create your own Private Link Service for Azure Storage.

Azure Storage is already an Azure service that supports Private Link.

---

# 13. Can a Private Endpoint be used without a Private Link Service?

Yes.

This demo proves that.

```text
VM
 |
 v
Private Endpoint
 |
 v
Azure Storage
```

The Azure service is the provider.

You only create the Private Endpoint.

---

# 14. Can Private Link Service be used without a Private Endpoint?

A Private Link Service is the provider-side component.

A consumer needs a Private Endpoint to privately consume that service.

Therefore, in a complete consumer/provider Private Link architecture, they work together:

```text
Consumer
Private Endpoint
       |
       v
Private Link Service
       |
       v
Provider service
```

For Azure Storage, Azure manages the service side.

---

# 15. Testing Strategy

Perform the demonstration in stages.

## Stage 1 — Storage Account with public access

Verify that the VM can access the Storage Account.

Document:

- Storage hostname
- DNS result
- Connectivity result
- Whether the destination is public/private

---

## Stage 2 — Create Private Endpoint

Create the Private Endpoint for the Blob service.

Document:

- Private Endpoint name
- Subnet
- Private IP
- Target Storage Account
- Sub-resource

---

## Stage 3 — Configure Private DNS

Configure the Private DNS Zone and VNet link.

Verify that the Storage Account hostname resolves to the Private Endpoint private IP from the VM.

---

## Stage 4 — Verify connectivity

From the VM, verify:

```text
Storage hostname
        ↓
Private IP
        ↓
Private Endpoint
        ↓
Storage Account
```

The important proof is the DNS resolution.

---

## Stage 5 — Disable public network access

After private connectivity has been verified, disable public network access on the Storage Account.

Now the expected architecture is:

```text
VM
 |
 | Private IP
 v
Private Endpoint
 |
 | Private Link
 v
Storage Account
```

The VM should continue to access the Storage Account.

This proves that the VM is using the private endpoint rather than depending on public access.

---

# 16. What should be visible during the demo?

Capture the following evidence.

### Evidence 1 — VM

Show:

```text
VM
 |
 VNet
 |
 Subnet
 |
 Private IP
```

### Evidence 2 — Storage Account

Show:

```text
Storage Account
 |
 Blob service
 |
 Public network access
```

### Evidence 3 — Private Endpoint

Show:

```text
Private Endpoint
 |
 Private IP
 |
 VNet
 |
 Subnet
 |
 Target resource
```

### Evidence 4 — Private DNS

Show:

```text
Private DNS Zone
 |
 Storage hostname record
 |
 Private IP
```

### Evidence 5 — DNS from VM

Show that:

```text
storage hostname
        ↓
private IP
```

### Evidence 6 — Connectivity after public access is disabled

Show that the VM can still reach the Storage Account.

This is the strongest proof of the private endpoint configuration.

---

# 17. Key Teaching Questions

## Question 1

Does the Storage Account get a NIC inside my VNet?

Answer:

No.

The Private Endpoint gets a network interface and private IP in your VNet.

---

## Question 2

Where does the private IP belong?

Answer:

The private IP belongs to the Private Endpoint's network interface.

---

## Question 3

Does the VM connect directly to the Storage Account's private IP?

Answer:

The VM connects to the Private Endpoint private IP.

Azure Private Link provides the service-side connectivity.

---

## Question 4

Why is DNS important?

Because applications normally use the Storage Account hostname rather than the Private Endpoint IP.

DNS allows the same hostname to resolve to the private endpoint when private connectivity is configured.

---

## Question 5

Do I need Private Link Service for Storage?

No.

Azure Storage already supports Private Link.

You create a Private Endpoint for the Storage Account.

---

# 18. Expected Final Architecture

```text
                         Azure
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  VNet                                                        │
│  10.0.0.0/16                                                │
│                                                              │
│  ┌────────────────┐       ┌─────────────────────────────┐   │
│  │ VM Subnet      │       │ Private Endpoint Subnet     │   │
│  │                │       │                             │   │
│  │   ┌────────┐   │       │   ┌─────────────────────┐   │   │
│  │   │   VM   │───┼───────┼──►│ Private Endpoint    │   │   │
│  │   │        │   │       │   │ Private IP          │   │   │
│  │   └────────┘   │       │   └──────────┬──────────┘   │   │
│  └────────────────┘       └──────────────┼──────────────┘   │
│                                          │                  │
│                                          │ Private Link     │
│                                          ▼                  │
│                                  ┌─────────────────────┐    │
│                                  │ Azure Storage       │    │
│                                  │ Blob Service        │    │
│                                  └─────────────────────┘    │
│                                                              │
│  Private DNS                                                 │
│  privatelink.blob.core.windows.net                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

# 19. Final Learning Outcome

After completing the demo, you should be able to explain:

- What an Azure Private Endpoint is
- Why a Private Endpoint receives a private IP
- How a VM accesses an Azure PaaS service privately
- How Private Link works at a high level
- Why DNS is critical
- What the Private DNS Zone does
- Difference between public and private service access
- Difference between Private Endpoint and Private Link Service
- Why Storage does not require the customer to deploy a Private Link Service
- How to prove that traffic is using private connectivity
- Why public network access can be disabled after private connectivity is established

---

# 20. One-Sentence Summary

> **A Private Endpoint places a private IP inside your VNet that represents a private entry point to an Azure service, allowing resources such as VMs to access that service through Azure Private Link without relying on the service's public endpoint.**
