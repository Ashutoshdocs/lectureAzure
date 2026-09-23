# AZ-104 — Microsoft Azure Administrator

> **AZ-104: Microsoft Azure Administrator**
> A practical roadmap for understanding what an Azure Administrator is expected to **know, configure, troubleshoot, secure, and operate** in Microsoft Azure.

---

## 🎯 What is AZ-104?

**AZ-104: Microsoft Azure Administrator** is the certification focused on administering Azure resources and services.

The certification is designed around the day-to-day responsibilities of an **Azure Administrator**.

An Azure Administrator should be able to:

* Create and manage Azure resources
* Configure networking
* Manage identities and access
* Configure storage
* Deploy and manage compute resources
* Monitor Azure infrastructure
* Implement backup and recovery
* Troubleshoot common Azure issues
* Apply security and governance controls
* Automate repetitive administrative tasks

The goal is **not simply to know what an Azure service is**.

The goal is to understand:

> **"Given an Azure requirement or problem, can I configure and operate the correct Azure solution?"**

---

# 🧑‍💻 What is expected from an AZ-104 Certified Administrator?

An AZ-104 certified administrator should be comfortable working with Azure from both:

```text
Azure Portal
     │
     ├── Azure CLI
     │
     ├── PowerShell
     │
     ├── ARM / Bicep
     │
     └── Azure Resource Manager
```

You should understand both:

### WHAT

What Azure service should be used?

### WHY

Why is that service appropriate?

### HOW

How do I configure it?

### TROUBLESHOOTING

What do I check when it does not work?

---

# 📚 AZ-104 Core Skill Areas

The AZ-104 certification broadly revolves around five major areas.

---

## 1️⃣ Manage Azure Identities and Governance

An administrator must understand how Azure resources are organized and controlled.

### You should understand:

* Microsoft Entra ID
* Users
* Groups
* Administrative units
* Subscriptions
* Resource groups
* Management groups
* Azure RBAC
* Role assignments
* Azure Policy
* Resource locks
* Tags
* Azure resource organization
* Management and governance concepts

### Example

A company has:

```text
Management Group
       │
       ├── Production Subscription
       │       │
       │       └── Production RG
       │
       └── Development Subscription
               │
               └── Development RG
```

You should be able to determine:

* Where should a resource be deployed?
* Who should have access?
* What permissions should they receive?
* Where should a policy be applied?
* Should a resource be locked?
* How can resources be identified using tags?

---

# 🔐 Azure RBAC

You should understand:

```text
Who
 │
 └── User / Group / Service Principal / Managed Identity
          │
          ▼
      Role Assignment
          │
          ▼
       Scope
          │
          ├── Management Group
          ├── Subscription
          ├── Resource Group
          └── Resource
```

You should be able to distinguish between:

* Owner
* Contributor
* Reader
* User Access Administrator
* Built-in roles
* Custom roles

And understand **scope inheritance**.

---

# 2️⃣ Implement and Manage Storage

An administrator should understand Azure storage and be able to choose the correct storage solution.

## Azure Storage Services

You should understand:

### Storage Account

The fundamental container for Azure Storage services.

```text
Storage Account
       │
       ├── Blob Storage
       │
       ├── File Shares
       │
       ├── Queues
       │
       └── Tables
```

---

## 🗄️ Blob Storage

Understand:

* Containers
* Blobs
* Access tiers
* Hot
* Cool
* Cold
* Archive
* Blob lifecycle management
* Blob versioning
* Soft delete
* Replication
* SAS
* Storage access keys
* Microsoft Entra-based access

---

## 📁 Azure Files

Understand:

* Azure file shares
* SMB
* NFS
* Storage account integration
* Mounting Azure Files
* Azure File Sync
* Snapshots

Example:

```text
On-Premises File Server
        │
        │ File Sync
        ▼
Azure File Share
        │
        ├── VM
        ├── Windows Server
        └── Multiple clients
```

---

## 🌍 Storage Redundancy

Understand the purpose and differences between:

* LRS
* ZRS
* GRS
* GZRS
* RA-GRS
* RA-GZRS

The administrator should be able to select redundancy based on:

```text
Availability requirement
        +
Disaster recovery requirement
        +
Cost
        ↓
Storage redundancy choice
```

---

# 3️⃣ Deploy and Manage Azure Compute Resources

An Azure Administrator should be comfortable deploying and managing compute.

## 🖥️ Azure Virtual Machines

You should understand:

* VM creation
* VM sizes
* Disks
* OS disks
* Data disks
* Temporary disks
* Managed disks
* Availability concepts
* VM networking
* NSGs
* Extensions
* VM Scale Sets
* VM administration
* VM backup
* VM monitoring

---

## 💾 Managed Disks

Understand:

* Standard HDD
* Standard SSD
* Premium SSD
* Premium SSD v2
* Ultra Disk
* Disk snapshots
* Disk images
* Disk resizing

Example recovery workflow:

```text
VM
 │
 ▼
Managed Disk
 │
 ▼
Snapshot
 │
 ▼
New Managed Disk
 │
 ▼
New VM
```

---

# 🌐 Azure App Services

Understand:

* App Service
* App Service Plan
* Web Apps
* Deployment
* Configuration
* Application settings
* Deployment slots
* Scaling
* Custom domains
* TLS/SSL
* Networking

You should understand the difference between:

```text
VM
 │
 └── You manage OS + runtime + application

App Service
 │
 └── Azure manages much of the underlying infrastructure
```

---

# 📦 Azure Container Services

You should understand Azure container deployment concepts, including:

* Azure Container Instances
* Azure Container Apps
* Container images
* Environment configuration
* Container networking
* Scaling concepts

You should understand when a container-based workload is more appropriate than a traditional VM.

---

# 4️⃣ Implement and Manage Virtual Networking

Networking is one of the most important skills for an Azure Administrator.

You should be comfortable with:

* Virtual Networks
* Subnets
* IP addressing
* Public IP addresses
* Private IP addresses
* Network Security Groups
* Application Security Groups
* Route tables
* User Defined Routes
* Network interfaces
* DNS
* VNet peering
* VPN concepts
* Private endpoints
* Service endpoints
* Azure Load Balancer
* Network troubleshooting

---

# 🏗️ Azure VNet

Basic architecture:

```text
Azure VNet
│
├── Subnet-Frontend
│      └── Web VM
│
├── Subnet-App
│      └── Application VM
│
└── Subnet-Database
       └── Database
```

You should understand:

* Address spaces
* Subnet ranges
* IP allocation
* Network interfaces
* Public vs private IP

---

# 🛡️ Network Security Group

You should understand how NSG rules control traffic.

```text
Internet
   │
   ▼
Public IP
   │
   ▼
NIC / Subnet
   │
   ▼
NSG
   │
   ├── Allow
   └── Deny
```

You should be able to troubleshoot questions such as:

> "The VM is running, but I cannot connect to port 80."

Possible checks:

```text
VM running?
      ↓
Public IP correct?
      ↓
NIC attached?
      ↓
NSG allows port 80?
      ↓
OS firewall allows port 80?
      ↓
Application listening on port 80?
```

---

# 🔗 VNet Peering

Understand:

```text
VNet-A
10.0.0.0/16
     │
     │ Peering
     │
VNet-B
10.1.0.0/16
```

You should understand:

* Why peering is used
* Address-space requirements
* Communication between VNets
* Regional and global peering concepts
* Routing implications

---

# 🌐 Azure DNS

Understand:

### Public DNS

Used for internet-facing DNS resolution.

```text
www.example.com
        │
        ▼
Azure Public DNS
        │
        ▼
Public IP
```

### Private DNS

Used for private name resolution inside Azure/private networks.

```text
VM
 │
 └── app.internal.example.com
              │
              ▼
       Private DNS Zone
              │
              ▼
        Private IP
```

You should understand when to use public vs private DNS.

---

# 🔒 Private Endpoint

Understand the architecture:

```text
VM
 │
 ▼
Private Endpoint
 │
 ▼
Private IP
 │
 ▼
Azure PaaS Service
```

The important concept is:

> Access to the Azure service can occur through a private IP address inside the virtual network.

---

# ⚖️ Azure Load Balancer

Understand:

```text
                Load Balancer
                     │
            ┌────────┴────────┐
            ▼                 ▼
          VM-01             VM-02
```

You should understand:

* Frontend IP
* Backend pool
* Health probe
* Load-balancing rule
* Inbound NAT rule

---

# 5️⃣ Monitor and Maintain Azure Resources

An administrator must know how to determine whether Azure resources are working correctly.

You should understand:

* Azure Monitor
* Metrics
* Logs
* Log Analytics
* Alerts
* Action Groups
* Activity Log
* Diagnostic settings
* Network Watcher
* VM monitoring
* Application monitoring concepts

---

# 📊 Azure Monitor

Basic model:

```text
Azure Resources
      │
      ▼
Azure Monitor
      │
      ├── Metrics
      │
      ├── Logs
      │
      └── Alerts
```

Example:

> CPU usage exceeds 80%.

Possible workflow:

```text
VM
 │
 ▼
Azure Monitor
 │
 ▼
Metric
 │
 ▼
Alert Rule
 │
 ▼
Action Group
 │
 ├── Email
 ├── SMS
 └── Other notification/action
```

---

# 🔎 Log Analytics

You should understand:

* Log Analytics workspace
* KQL basics
* Collecting logs
* Querying logs
* Diagnostic settings
* Azure Monitor Agent concepts

Example KQL:

```kusto
Perf
| where CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by Computer
```

The goal is not to become a KQL developer.

The goal is to be able to **find useful operational information**.

---

# 💾 Backup and Disaster Recovery

An Azure Administrator should understand the difference between:

## Snapshot

Point-in-time copy of a disk.

```text
Managed Disk
     │
     ▼
 Snapshot
```

## Azure Backup

Used to provide backup and recovery capabilities.

```text
VM
 │
 ▼
Recovery Services Vault
 │
 ▼
Backup
```

## Azure Site Recovery

Used for disaster recovery and workload replication/failover scenarios.

Conceptually:

```text
Primary Region
     │
     │ Replication
     ▼
Secondary Region
```

You should understand **when each technology is appropriate**.

---

# 🧠 The AZ-104 Administrator Mindset

Being AZ-104 certified is not about memorizing hundreds of Azure services.

You should develop an administrator mindset.

When given a requirement, think:

```text
REQUIREMENT
     │
     ▼
What Azure service?
     │
     ▼
What configuration?
     │
     ▼
What permissions?
     │
     ▼
What networking?
     │
     ▼
What security?
     │
     ▼
How will I monitor it?
     │
     ▼
How will I recover it?
     │
     ▼
How will I troubleshoot it?
```

---

# 🧪 Practical Skills Expected

A strong AZ-104 administrator should be able to perform tasks such as:

### Identity

* Create users
* Create groups
* Assign Azure RBAC roles
* Understand role scope
* Implement resource locks
* Apply Azure Policy
* Organize resources using tags

### Storage

* Create storage accounts
* Create containers
* Upload blobs
* Configure access
* Create file shares
* Mount Azure Files
* Configure storage redundancy
* Configure lifecycle management

### Compute

* Create VMs
* Attach disks
* Resize VMs
* Configure VM networking
* Create VM Scale Sets
* Configure App Services
* Deploy container workloads

### Networking

* Create VNets
* Create subnets
* Configure NSGs
* Configure route tables
* Configure VNet peering
* Configure DNS
* Configure private endpoints
* Configure load balancing

### Monitoring

* Create Log Analytics workspaces
* Configure diagnostic settings
* Query logs
* Create alerts
* Configure action groups
* Troubleshoot VM/network issues

### Backup

* Configure VM backup
* Restore files
* Restore disks/VMs
* Understand recovery points
* Understand disaster recovery concepts

---

# 🛠️ Tools an Azure Administrator Should Know

You should be comfortable using multiple management interfaces.

## Azure Portal

Best for:

* Visual configuration
* Learning Azure services
* Troubleshooting
* Reviewing resource properties

---

## Azure CLI

Example:

```bash
az vm list -o table
```

```bash
az group list -o table
```

```bash
az network vnet list -o table
```

---

## Azure PowerShell

Example:

```powershell
Get-AzVM
```

```powershell
Get-AzResourceGroup
```

---

## Infrastructure as Code

Understand the concepts behind:

* ARM templates
* Bicep
* Declarative deployment

Example:

```text
Desired State
     │
     ▼
Bicep / ARM
     │
     ▼
Azure Resource Manager
     │
     ▼
Azure Resources
```

---

# 🔧 Troubleshooting Skills

One of the most important administrator skills is troubleshooting.

Do not simply ask:

> "Is the VM running?"

Instead use a structured approach.

---

## Example: Website Not Accessible

```text
User
 │
 ▼
DNS
 │
 ▼
Public IP
 │
 ▼
Load Balancer
 │
 ▼
NSG
 │
 ▼
NIC
 │
 ▼
VM
 │
 ▼
OS Firewall
 │
 ▼
Web Server
 │
 ▼
Application
```

Check each layer.

---

# 🧩 Scenario-Based Thinking

AZ-104 preparation should include scenarios.

For example:

### Scenario

A company has:

```text
Web VM
Application VM
Database
```

The requirement is:

* Web server must be publicly accessible.
* Application server should not have a public IP.
* Database should only be accessible by the application server.
* Administrators need secure access.
* The environment must be monitored.

You should be able to reason toward an architecture such as:

```text
Internet
   │
   ▼
Web Tier
   │
   ▼
Application Tier
   │
   ▼
Database Tier
```

with appropriate:

* VNets
* Subnets
* NSGs
* Private connectivity
* Identity
* Monitoring
* Backup

---

# 🎓 What Does "AZ-104 Certified" Really Mean?

The certification demonstrates that you have validated skills related to administering Azure environments.

But in a real job, certification alone is not enough.

A good Azure Administrator should be able to:

> **Deploy → Configure → Secure → Monitor → Troubleshoot → Recover**

Azure resources.

---

# 🚀 Recommended Learning Path

Follow this sequence:

```text
1. Azure Fundamentals
        ↓
2. Identity & Governance
        ↓
3. Storage
        ↓
4. Virtual Machines
        ↓
5. Networking
        ↓
6. App Services
        ↓
7. Containers
        ↓
8. Monitoring
        ↓
9. Backup & Recovery
        ↓
10. Troubleshooting
        ↓
11. Automation
        ↓
12. Scenario-Based Labs
```

---

# 🧪 Minimum Hands-On Lab Portfolio

Before considering yourself comfortable with AZ-104, build these labs.

## Lab 1 — Identity

```text
User
 ↓
Group
 ↓
RBAC Role
 ↓
Resource Group
```

---

## Lab 2 — Storage

```text
Storage Account
 ↓
Container
 ↓
Blob
 ↓
SAS / Access Control
```

---

## Lab 3 — Azure Files

```text
Storage Account
 ↓
File Share
 ↓
Linux / Windows VM
 ↓
Mount Share
```

---

## Lab 4 — Virtual Machine

```text
VNet
 ↓
Subnet
 ↓
NIC
 ↓
NSG
 ↓
VM
 ↓
Web Server
```

---

## Lab 5 — Networking

```text
VNet-A
   │
   │ Peering
   ▼
VNet-B
```

Test communication between resources.

---

## Lab 6 — Load Balancing

```text
Client
  │
  ▼
Load Balancer
  │
  ├── VM-01
  └── VM-02
```

---

## Lab 7 — Monitoring

```text
VM
 ↓
Azure Monitor
 ↓
Metric
 ↓
Alert
 ↓
Action Group
```

---

## Lab 8 — Backup

```text
VM
 ↓
Recovery Services Vault
 ↓
Backup
 ↓
Recovery
```

---

## Lab 9 — Private Endpoint

```text
VNet
 │
 ▼
Private Endpoint
 │
 ▼
Storage Account
```

Verify that access occurs privately.

---

# 🧭 Final AZ-104 Skill Checklist

Before the exam and before claiming practical administrator readiness, ask yourself:

### Identity

* [ ] Can I explain Microsoft Entra ID?
* [ ] Can I create users/groups?
* [ ] Can I assign RBAC?
* [ ] Do I understand RBAC scope?
* [ ] Can I use Azure Policy?
* [ ] Do I understand resource locks and tags?

### Storage

* [ ] Can I create a storage account?
* [ ] Do I understand Blob Storage?
* [ ] Do I understand Azure Files?
* [ ] Can I explain storage redundancy?
* [ ] Do I understand SAS?
* [ ] Do I understand lifecycle management?

### Compute

* [ ] Can I deploy a VM?
* [ ] Can I manage disks?
* [ ] Can I resize a VM?
* [ ] Can I configure VM networking?
* [ ] Do I understand VM Scale Sets?
* [ ] Do I understand App Service?
* [ ] Do I understand Azure container options?

### Networking

* [ ] Can I design a VNet?
* [ ] Can I create subnets?
* [ ] Can I configure NSGs?
* [ ] Do I understand routing?
* [ ] Can I configure VNet peering?
* [ ] Do I understand DNS?
* [ ] Do I understand Private Endpoint?
* [ ] Do I understand Load Balancer?

### Monitoring

* [ ] Do I understand Azure Monitor?
* [ ] Can I read metrics?
* [ ] Can I configure alerts?
* [ ] Can I use Log Analytics?
* [ ] Can I perform basic KQL queries?
* [ ] Can I troubleshoot Azure resources?

### Backup & Recovery

* [ ] Do I understand VM backup?
* [ ] Do I understand snapshots?
* [ ] Can I restore a resource?
* [ ] Do I understand Recovery Services Vault?
* [ ] Can I explain Azure Site Recovery?

### Administration

* [ ] Can I use Azure Portal?
* [ ] Can I use Azure CLI?
* [ ] Can I use PowerShell?
* [ ] Do I understand ARM/Bicep concepts?
* [ ] Can I troubleshoot systematically?

---

# 🏁 The AZ-104 Goal

The ultimate goal of AZ-104 preparation should be:

```text
                   AZURE ADMINISTRATOR
                           │
          ┌────────────────┼────────────────┐
          │                │                │
       IDENTITY          COMPUTE        STORAGE
          │                │                │
          └────────────────┼────────────────┘
                           │
                       NETWORKING
                           │
                    MONITORING
                           │
                    BACKUP / DR
                           │
                     SECURITY
                           │
                     AUTOMATION
                           │
                           ▼
                    TROUBLESHOOTING
```

### Remember:

> **AZ-104 is about administering Azure, not merely memorizing Azure services.**

A capable administrator should be able to look at an Azure requirement, select the appropriate service, configure it securely, monitor it, troubleshoot it, and recover it when necessary.

---

## 📌 Certification Mindset

Prepare in three layers:

### Layer 1 — Theory

Understand **what** each Azure service does.

### Layer 2 — Configuration

Know **how** to configure the service using Portal, CLI, PowerShell, or IaC.

### Layer 3 — Scenarios

Understand **why one configuration/service is appropriate over another**.

```text
WHAT
 ↓
HOW
 ↓
WHY
 ↓
TROUBLESHOOT
 ↓
REAL-WORLD ADMINISTRATION
```

That is the mindset to develop while preparing for **AZ-104: Microsoft Azure Administrator**.
