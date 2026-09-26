# Azure Private Link Service Lab — End-to-End Architecture and Steps

## 🎯 Objective

This lab demonstrates **Azure Private Link Service (PLS)** end to end.

The lab creates two completely separate VNets:

- **Provider VNet** — hosts the application/server being published.
- **Consumer VNet** — hosts the client that wants private access to the provider service.

The two VNets are deliberately **not peered**.

The consumer reaches the provider application only through:

```text
Consumer VM
     |
     v
Private Endpoint
     |
     | Azure Private Link
     v
Private Link Service
     |
     v
Standard Internal Load Balancer
     |
     v
Provider VM
     |
     v
Nginx
```

The provider VM has **no public IP**.

---

# 1. Architecture

```text
                         AZURE

        CONSUMER VNET                         PROVIDER VNET
        10.20.0.0/16                         10.10.0.0/16
┌───────────────────────────┐          ┌────────────────────────────┐
│                           │          │                            │
│  Consumer VM              │          │  Provider VM               │
│  vmconsumer               │          │  vmproduction              │
│  10.20.1.x                │          │  10.10.1.x                 │
│                           │          │  Nginx :80                 │
│        │                  │          │       ▲                    │
│        │                  │          │       │                    │
│        ▼                  │          │  Internal Load Balancer     │
│  Private Endpoint         │          │  10.10.1.100:80            │
│  10.20.2.x                │          │       ▲                    │
│        │                  │          │       │                    │
└────────┼──────────────────┘          │  Private Link Service      │
         │                             │       ▲                    │
         │ Azure Private Link          │       │                    │
         └─────────────────────────────┼───────┘                    │
                                       │                            │
                                       └────────────────────────────┘

             ❌ NO VNET PEERING
             ❌ NO PUBLIC IP ON PROVIDER VM
             ❌ NO ROUTE BETWEEN THE TWO VNets
             ✅ PRIVATE ENDPOINT → PLS → INTERNAL LB → VM
```

---

# 2. Provider and Consumer

## Provider

The provider owns the application:

```text
Provider VNet
10.10.0.0/16
```

Inside it:

```text
vmproduction
    |
    v
Nginx
```

The provider VM has:

```text
NO PUBLIC IP
```

The application is exposed internally through:

```text
Standard Internal Load Balancer
10.10.1.100:80
```

The Private Link Service is attached to the Load Balancer frontend.

---

## Consumer

The consumer owns a different VNet:

```text
Consumer VNet
10.20.0.0/16
```

Inside it:

```text
vmconsumer
```

The consumer creates:

```text
Private Endpoint
```

The Private Endpoint receives a private IP such as:

```text
10.20.2.4
```

The consumer connects to this IP.

---

# 3. Why Private Link Service Is Needed Here

A Private Link Service is useful when **you own the application/service** and want other VNets to consume it privately.

The provider architecture is:

```text
Your Application
      |
      v
Standard Internal Load Balancer
      |
      v
Private Link Service
```

The consumer architecture is:

```text
Private Endpoint
      |
      v
Private Link Service
```

The two are connected by Azure Private Link.

---

# 4. Important Difference From a Normal Private Endpoint

For an Azure-managed PaaS service such as Storage:

```text
Consumer VNet
     |
     v
Private Endpoint
     |
     v
Azure Storage
```

You normally do **not** create a Private Link Service.

For your own service:

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
Internal Load Balancer
     |
     v
Your VM/application
```

This lab demonstrates the second architecture.

---

# 5. Lab Address Plan

## Provider VNet

```text
VNet:
10.10.0.0/16
```

Subnets:

```text
Provider VM subnet:
10.10.1.0/24

PLS/NAT subnet:
10.10.2.0/24
```

Internal Load Balancer:

```text
10.10.1.100
```

---

## Consumer VNet

```text
VNet:
10.20.0.0/16
```

Subnets:

```text
Consumer VM subnet:
10.20.1.0/24

Private Endpoint subnet:
10.20.2.0/24
```

---

# 6. Resources Created

The lab creates:

```text
Resource Group
│
├── Provider VNet
│   ├── Provider VM subnet
│   └── PLS/NAT subnet
│
├── Consumer VNet
│   ├── Consumer VM subnet
│   └── Private Endpoint subnet
│
├── NAT Gateway
│
├── Provider NSG
│
├── Standard Internal Load Balancer
│
├── Provider VM
│   └── Nginx
│
├── Consumer VM
│
├── Private Link Service
│
└── Private Endpoint
```

---

# 7. Requirements

Install Azure CLI and PowerShell.

Login:

```powershell
az login
```

Verify the subscription:

```powershell
az account show -o table
```

The supplied deployment script requires Azure CLI and supports Windows PowerShell 5.1 and PowerShell 7+. fileciteturn0file0L23-L35

---

# 8. Deployment Script

Save the supplied PowerShell script as:

```text
Deploy-PrivateLinkLab.ps1
```

The script accepts:

```powershell
-ResourceGroup
-Location
-VmSize
-AdminUser
-AdminPassword
-Image
```

Example:

```powershell
.\Deploy-PrivateLinkLab.ps1
```

Or:

```powershell
.\Deploy-PrivateLinkLab.ps1 `
  -ResourceGroup rg-pls-lab `
  -Location centralindia
```

The default location in the supplied script is:

```text
centralindia
```

and the default resource group is:

```text
rg-pls-nginx-demo
```

fileciteturn0file0L37-L44

---

# 9. Step 1 — Create Provider VNet

The provider VNet is:

```text
vnet-provider
10.10.0.0/16
```

Provider VM subnet:

```text
snet-provider-vm
10.10.1.0/24
```

PLS/NAT subnet:

```text
snet-pls-nat
10.10.2.0/24
```

The PLS subnet has Private Link Service network policies disabled.

fileciteturn0file0L50-L59

Architecture:

```text
vnet-provider
10.10.0.0/16
│
├── snet-provider-vm
│   10.10.1.0/24
│
└── snet-pls-nat
    10.10.2.0/24
```

---

# 10. Step 2 — Create Consumer VNet

The consumer VNet is:

```text
vnet-consumer
10.20.0.0/16
```

Subnets:

```text
snet-consumer-vm
10.20.1.0/24
```

and:

```text
snet-private-endpoint
10.20.2.0/24
```

The Private Endpoint subnet has Private Endpoint network policies disabled.

fileciteturn0file0L57-L59

Architecture:

```text
vnet-consumer
10.20.0.0/16
│
├── snet-consumer-vm
│   10.20.1.0/24
│
└── snet-private-endpoint
    10.20.2.0/24
```

---

# 11. Step 3 — NAT Gateway

The provider VM has **no public IP**.

However, it needs outbound Internet access during deployment to install Nginx.

Therefore the lab creates:

```text
NAT Gateway
    |
    v
Provider VM subnet
```

The NAT Gateway provides outbound Internet connectivity while keeping the provider VM without a public IP.

The supplied script creates a Standard Public IP, NAT Gateway, and attaches it to the provider VM subnet. fileciteturn0file0L450-L464

Important:

```text
NAT Gateway
     ≠
Public IP on VM
```

The VM itself remains private.

---

# 12. Step 4 — Provider VM

The provider VM is:

```text
vmproduction
```

It is deployed without a public IP.

The VM runs:

```text
Nginx
```

The supplied cloud-init configuration installs Nginx and creates the demonstration web page. fileciteturn0file0L503-L520

The provider side becomes:

```text
vmproduction
10.10.1.x
    |
    v
Nginx :80
```

---

# 13. Step 5 — Internal Load Balancer

Create a:

```text
Standard Internal Load Balancer
```

Frontend:

```text
10.10.1.100
```

Port:

```text
80
```

Backend:

```text
vmproduction
```

The supplied script creates the Standard Load Balancer, HTTP health probe, and TCP forwarding rule. fileciteturn0file0L481-L500

Architecture:

```text
              Internal LB
              10.10.1.100:80
                    |
                    v
             vmproduction
                 Nginx
```

---

# 14. Why Standard Load Balancer?

Private Link Service is attached to a Load Balancer frontend.

The lab therefore uses:

```text
Standard Internal Load Balancer
```

The Load Balancer:

1. Provides the frontend IP.
2. Performs health probing.
3. Sends traffic to the backend VM.
4. Provides the frontend configuration used by the PLS.

---

# 15. Step 6 — Create Private Link Service

The Private Link Service is:

```text
pls-nginx-production
```

It is associated with:

```text
Provider VNet
```

and:

```text
Internal Load Balancer
```

The supplied script creates the PLS using the provider VNet, PLS subnet, Load Balancer, and Load Balancer frontend configuration. fileciteturn0file0L537-L546

The architecture becomes:

```text
Private Link Service
        |
        v
Internal Load Balancer
        |
        v
vmproduction
        |
        v
Nginx
```

---

# 16. Step 7 — Create Private Endpoint

The consumer creates:

```text
pe-nginx-consumer
```

inside:

```text
vnet-consumer
```

and:

```text
snet-private-endpoint
10.20.2.0/24
```

The Private Endpoint connects to the Private Link Service.

fileciteturn0file0L549-L559

The resulting architecture:

```text
Consumer VNet
10.20.0.0/16

Private Endpoint
10.20.2.x
      |
      |
      v
Private Link Service
      |
      v
Internal Load Balancer
10.10.1.100
      |
      v
Provider VM
10.10.1.x
```

---

# 17. ⭐ The Most Important Concept

The two VNets are:

```text
Provider:
10.10.0.0/16

Consumer:
10.20.0.0/16
```

They are **not peered**.

There is no normal VNet route between them.

The supplied lab explicitly uses this design so the consumer can reach the Nginx service only through the Private Endpoint → Private Link Service path. fileciteturn0file0L13-L21

---

# 18. Packet Flow

A request from the consumer follows this path:

```text
vmconsumer
10.20.1.x
    |
    | HTTP :80
    v
Private Endpoint
10.20.2.x
    |
    | Azure Private Link
    v
Private Link Service
    |
    | PLS NAT
    v
Internal Load Balancer
10.10.1.100:80
    |
    v
vmproduction
10.10.1.x
    |
    v
Nginx
```

The supplied lab describes the packet walk as:

1. Consumer VM sends the request to the Private Endpoint IP.
2. Azure carries the flow over the backbone to the PLS.
3. PLS rewrites the source to a NAT IP from `10.10.2.0/24`.
4. Internal Load Balancer forwards the traffic to a healthy backend.
5. Nginx responds through the same architecture. fileciteturn0file0L246-L254

---

# 19. Step 8 — Verify Deployment

The script waits for cloud-init and verifies:

```text
nginx
```

and:

```text
/health
```

on the provider VM. fileciteturn0file0L563-L569

---

# 20. Get Private Endpoint IP

The deployment script displays:

```text
Private Endpoint IP : <PRIVATE_ENDPOINT_IP>
```

The IP belongs to:

```text
Consumer VNet
snet-private-endpoint
10.20.2.0/24
```

For example:

```text
10.20.2.4
```

---

# 21. Connect to Consumer VM

Get the consumer VM public IP:

```powershell
az vm show -d `
  -g $ResourceGroup `
  -n vmconsumer `
  --query publicIps `
  -o tsv
```

SSH:

```powershell
ssh azureuser@<CONSUMER_PUBLIC_IP>
```

The consumer VM has a public IP only so that you can SSH into it for the practical.

---

# 22. Test the Private Endpoint

From `vmconsumer`:

```bash
curl http://<PRIVATE_ENDPOINT_IP>/health
```

Expected:

```text
healthy
```

Then:

```bash
curl http://<PRIVATE_ENDPOINT_IP>/
```

The terminal-oriented page will be returned.

The supplied deployment script performs the same health and HTTP tests from `vmconsumer`. fileciteturn0file0L564-L575

---

# 23. Test the HTML Page

From the consumer VM:

```bash
curl http://<PRIVATE_ENDPOINT_IP>/html
```

Or open the endpoint from a suitable browser if you have a route into the consumer VNet.

The provider's Nginx server has separate terminal and browser-friendly representations. fileciteturn0file0L18-L21

---

# 24. ⭐ Prove the Provider VM Has No Public IP

Run:

```powershell
az vm show -d `
  -g $ResourceGroup `
  -n vmproduction `
  --query "{PrivateIP:privateIps,PublicIP:publicIps}" `
  -o json
```

Expected conceptually:

```json
{
  "PrivateIP": "10.10.1.x",
  "PublicIP": ""
}
```

This proves the provider application is not exposed directly to the Internet.

---

# 25. ⭐ Prove the VNets Are Not Peered

List VNet peerings:

```powershell
az network vnet peering list `
  -g $ResourceGroup `
  --vnet-name vnet-provider `
  -o table
```

Then:

```powershell
az network vnet peering list `
  -g $ResourceGroup `
  --vnet-name vnet-consumer `
  -o table
```

There should be no provider-consumer VNet peering.

This is important because the demo is intended to show that Private Link provides the service connection without VNet peering. The supplied lab explicitly states that the VNets are not peered. fileciteturn0file0L13-L16

---

# 26. ⭐ Prove Private Link Service Exists

```powershell
az network private-link-service list `
  -g $ResourceGroup `
  -o table
```

You should see:

```text
pls-nginx-production
```

---

# 27. ⭐ Prove Private Endpoint Exists

```powershell
az network private-endpoint list `
  -g $ResourceGroup `
  -o table
```

You should see:

```text
pe-nginx-consumer
```

---

# 28. ⭐ Check Private Endpoint Connection State

```powershell
az network private-endpoint show `
  -g $ResourceGroup `
  -n pe-nginx-consumer `
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState" `
  -o json
```

You want the connection status to be:

```text
Approved
```

The supplied script captures and displays the Private Endpoint connection state after creation. fileciteturn0file0L546-L560

---

# 29. ⭐ Understand the Source IP

One of the most important PLS concepts is **source NAT**.

The provider backend does not necessarily see the consumer VM's original:

```text
10.20.x.x
```

Instead, the PLS can use a NAT IP from the provider-side PLS subnet:

```text
10.10.2.x
```

Conceptually:

```text
Consumer VM
10.20.1.x
     |
     v
Private Endpoint
10.20.2.x
     |
     v
Private Link Service
     |
     | SNAT
     v
10.10.2.x
     |
     v
Internal LB
     |
     v
Provider VM
10.10.1.x
```

The supplied demonstration page explicitly shows the request source IP and notes that the server sees a PLS NAT address rather than the consumer's `10.20.x.x` address. fileciteturn0file0L258-L266

---

# 30. Why Use Two Different VNets?

This is one of the strongest teaching parts of the lab.

```text
Provider:
10.10.0.0/16

Consumer:
10.20.0.0/16
```

There is no peering.

Therefore:

```text
Consumer VM
    X
    X  Direct VNet routing
    X
Provider VM
```

But:

```text
Consumer VM
    |
    v
Private Endpoint
    |
    v
Private Link Service
    |
    v
Internal Load Balancer
    |
    v
Provider VM
```

works.

---

# 31. What This Demonstrates

This lab demonstrates that a provider can publish a private application without giving consumers:

- A public IP for the application
- Direct access to the provider VNet
- VNet peering
- Provider-side routing to the consumer VNet
- Access to the provider's entire address space

The consumer gets access to the **published service**, not the provider network.

---

# 32. Private Link Service vs Private Endpoint

## Private Link Service

Provider side:

```text
Provider Application
        |
        v
Internal Standard LB
        |
        v
Private Link Service
```

The PLS publishes the provider service.

---

## Private Endpoint

Consumer side:

```text
Private Endpoint
      |
      v
Private Link Service
```

The PE gives the consumer a private IP through which it consumes the published service.

---

# 33. Complete Architecture

```text
                    CONSUMER
               VNet 10.20.0.0/16
        ┌──────────────────────────────┐
        │                              │
        │  vmconsumer                  │
        │  10.20.1.x                   │
        │       │                      │
        │       ▼                      │
        │  Private Endpoint            │
        │  10.20.2.x                   │
        │       │                      │
        └───────┼──────────────────────┘
                │
                │
          Azure Private Link
                │
                │
        ┌───────┼──────────────────────┐
        │       ▼                      │
        │ Private Link Service         │
        │                              │
        │       │                      │
        │       ▼                      │
        │ Internal Load Balancer       │
        │ 10.10.1.100:80               │
        │       │                      │
        │       ▼                      │
        │ vmproduction                 │
        │ 10.10.1.x                    │
        │       │                      │
        │       ▼                      │
        │ Nginx                        │
        │                              │
        │ PROVIDER VNet                │
        │ 10.10.0.0/16                 │
        └──────────────────────────────┘

              NO VNET PEERING
              NO PUBLIC IP ON APP VM
              PRIVATE SERVICE PUBLISHED
```

---

# 34. Private Endpoint Without PLS vs Private Endpoint With PLS

This distinction is extremely important.

### Azure-managed PaaS

```text
Consumer VNet
      |
      v
Private Endpoint
      |
      v
Azure Storage / SQL / Key Vault / etc.
```

Usually:

```text
Private Link Service
        ❌
```

because Microsoft manages the service side.

---

### Your own application

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
Standard Internal Load Balancer
      |
      v
Your VM / Application
```

This lab demonstrates this architecture.

---

# 35. Useful Verification Commands

### Provider VM

```powershell
az vm show -d -g $ResourceGroup -n vmproduction `
  --query "{PrivateIP:privateIps,PublicIP:publicIps}" -o json
```

### Consumer VM

```powershell
az vm show -d -g $ResourceGroup -n vmconsumer `
  --query "{PrivateIP:privateIps,PublicIP:publicIps}" -o json
```

### Private Link Service

```powershell
az network private-link-service show `
  -g $ResourceGroup `
  -n pls-nginx-production `
  -o json
```

### Private Endpoint

```powershell
az network private-endpoint show `
  -g $ResourceGroup `
  -n pe-nginx-consumer `
  -o json
```

### Load Balancer

```powershell
az network lb show `
  -g $ResourceGroup `
  -n ilb-production `
  -o json
```

### VNet Peering

```powershell
az network vnet peering list `
  -g $ResourceGroup `
  --vnet-name vnet-provider `
  -o table
```

### Test

```powershell
az vm run-command invoke `
  -g $ResourceGroup `
  -n vmconsumer `
  --command-id RunShellScript `
  --scripts "curl -fsS http://<PRIVATE_ENDPOINT_IP>/health"
```

---

# 36. Troubleshooting

## Problem: Private Endpoint connection is not approved

Check:

```powershell
az network private-endpoint show `
  -g $ResourceGroup `
  -n pe-nginx-consumer `
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState"
```

Check that the PLS and PE connection exists.

---

## Problem: `/health` fails

Check the provider VM:

```powershell
az vm run-command invoke `
  -g $ResourceGroup `
  -n vmproduction `
  --command-id RunShellScript `
  --scripts "systemctl status nginx" "curl -fsS http://localhost/health"
```

The supplied deployment script performs these checks during deployment. fileciteturn0file0L563-L569

---

## Problem: Load Balancer backend is unhealthy

Check the health probe:

```text
Protocol: HTTP
Port: 80
Path: /health
```

The provider VM must return:

```text
HTTP 200
healthy
```

---

## Problem: Consumer cannot connect

Verify:

```text
Consumer VM
      |
      v
Private Endpoint
      |
      v
PLS
      |
      v
Internal LB
      |
      v
Provider VM
```

Then check:

1. Private Endpoint connection state.
2. Private Endpoint IP.
3. PLS configuration.
4. Internal Load Balancer frontend.
5. Backend pool.
6. Health probe.
7. NSG allowing HTTP.
8. Nginx status.

---

# 37. Important Security Concept

The provider VM has:

```text
No public IP
```

The consumer VM has a public IP only for:

```text
SSH → vmconsumer
```

The actual application path is:

```text
vmconsumer
    |
    v
Private Endpoint
    |
    v
Private Link Service
    |
    v
Internal Load Balancer
    |
    v
vmproduction
```

The provider application itself is not exposed directly to the Internet.

---

# 38. Cleanup

When the lab is complete:

```powershell
az group delete `
  -n $ResourceGroup `
  --yes `
  --no-wait
```

This removes the complete lab environment.

The supplied script also prints the cleanup command after successful deployment. fileciteturn0file0L581-L606

---

# 🎓 Final Teaching Summary

### Private Endpoint

```text
Consumer
   |
   v
Private Endpoint
```

Provides the consumer with a private IP for accessing the published service.

### Private Link Service

```text
Private Link Service
       |
       v
Internal Load Balancer
       |
       v
Your application
```

Publishes your own application privately.

### Complete Private Link Service architecture

```text
                 CONSUMER
                    |
              Private Endpoint
                    |
                    v
              Azure Private Link
                    |
                    v
            Private Link Service
                    |
                    v
          Standard Internal LB
                    |
                    v
              Provider VM
                    |
                    v
                  Nginx
```

### One-line definition

> **Private Link Service allows you to privately publish your own application behind a Standard Load Balancer so consumers can access that application through a Private Endpoint without VNet peering or exposing the application VM to the public Internet.**
