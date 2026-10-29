# Azure Dedicated Host: Portal Setup Guide (with 2 VMs)

A step-by-step guide to setting up an **Azure Dedicated Host** and placing **two virtual machines** on it, using only the **Azure Portal** (no CLI or scripts).

---

## Table of Contents

1. [What is Azure Dedicated Host?](#1-what-is-azure-dedicated-host)
2. [Key Concepts](#2-key-concepts)
3. [Architecture of This Lab](#3-architecture-of-this-lab)
4. [Prerequisites](#4-prerequisites)
5. [Step 1: Create a Resource Group](#step-1-create-a-resource-group)
6. [Step 2: Create a Host Group](#step-2-create-a-host-group)
7. [Step 3: Create a Dedicated Host](#step-3-create-a-dedicated-host)
8. [Step 4: Create a Virtual Network](#step-4-create-a-virtual-network)
9. [Step 5: Create VM 1 on the Dedicated Host](#step-5-create-vm-1-on-the-dedicated-host)
10. [Step 6: Create VM 2 on the Dedicated Host](#step-6-create-vm-2-on-the-dedicated-host)
11. [Step 7: Verify the Setup](#step-7-verify-the-setup)
12. [Moving an Existing VM onto a Dedicated Host](#moving-an-existing-vm-onto-a-dedicated-host)
13. [Billing Notes](#billing-notes)
14. [Troubleshooting](#troubleshooting)
15. [Clean Up](#clean-up)
16. [Quick Reference Checklist](#quick-reference-checklist)

---

## 1. What is Azure Dedicated Host?

Azure Dedicated Host gives you a **physical server in an Azure datacenter that is used only by your subscription**. No other customer's VMs run on that hardware. You then place your own VMs on it.

**Why use it?**

| Need | How Dedicated Host helps |
|---|---|
| Compliance / regulatory isolation | Hardware is not shared with other tenants |
| Software licensing (per-core / per-socket) | Visibility into physical cores; works with Azure Hybrid Benefit for Windows Server and SQL Server |
| Maintenance control | You can choose a maintenance window for host-level updates (via Maintenance Configurations) |
| Predictable placement | You decide which VMs share which host and fault domain |

---

## 2. Key Concepts

| Term | Meaning |
|---|---|
| **Host Group** | A logical container for dedicated hosts. Tied to **one region** and optionally **one availability zone**. Defines the number of **fault domains**. |
| **Dedicated Host** | The physical server. You choose its **SKU (host family)**, e.g. `Dsv3-Type1`, `Esv5-Type1`. The SKU decides which VM sizes can run on it and how many. |
| **Fault Domain (FD)** | A group of hardware sharing power/network. Spreading hosts across FDs protects against rack-level failure. |
| **Automatic placement** | Optional host group setting that lets Azure pick the host for a VM automatically. |
| **VM series compatibility** | A VM can only run on a host whose family matches its series (e.g. a `D4s_v3` VM needs a `Dsv3` host). |

```
Region (e.g. Central India)
└── Availability Zone 1
    └── Host Group  (fault domains: 1–3)
        └── Dedicated Host  (SKU: Dsv3-Type1, FD 0)
            ├── VM 1  (Standard_D2s_v3)
            └── VM 2  (Standard_D2s_v3)
```

---

## 3. Architecture of This Lab

```
┌───────────────────────────────────────────────────────────────┐
│ Resource Group: rg-dedicatedhost-lab                          │
│                                                               │
│  ┌────────────────────────────┐   ┌────────────────────────┐  │
│  │ Host Group: hg-lab-01      │   │ VNet: vnet-dh-lab      │  │
│  │ Zone 1 | Fault domains: 1  │   │ 10.0.0.0/16            │  │
│  │                            │   │  └─ snet-vms           │  │
│  │  ┌──────────────────────┐  │   │     10.0.1.0/24        │  │
│  │  │ Host: dh-lab-01      │  │   └───────────┬────────────┘  │
│  │  │ SKU: Dsv3-Type1      │  │               │               │
│  │  │                      │  │               │               │
│  │  │  ┌──────┐  ┌──────┐  │◄─┼───────────────┘               │
│  │  │  │ VM 1 │  │ VM 2 │  │  │                               │
│  │  │  └──────┘  └──────┘  │  │                               │
│  │  └──────────────────────┘  │                               │
│  └────────────────────────────┘                               │
└───────────────────────────────────────────────────────────────┘
```

**Values used in this guide** (change to suit your environment):

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-dedicatedhost-lab` | |
| Region | `Central India` | Use any region that offers your host SKU |
| Availability zone | `Zone 1` | Optional, but recommended |
| Host group | `hg-lab-01` | 1 fault domain |
| Dedicated host | `dh-lab-01` | `Dsv3-Type1` |
| Virtual network | `vnet-dh-lab` | `10.0.0.0/16` |
| Subnet | `snet-vms` | `10.0.1.0/24` |
| VM 1 | `vm-dh-01` | `Standard_D2s_v3` |
| VM 2 | `vm-dh-02` | `Standard_D2s_v3` |

---

## 4. Prerequisites

- [ ] An Azure subscription **(free trial and some sponsorship subscriptions do not support Dedicated Host)**, typically Pay-As-You-Go, EA or CSP.
- [ ] **Contributor** (or Owner) role on the subscription or resource group.
- [ ] Enough **vCPU quota** for the host family in your chosen region.
  - Portal: **Subscriptions → your subscription → Usage + quotas** → filter by the host family (e.g. "Dedicated Host" / "DSv3 Family") → **Request increase** if needed.
- [ ] A region that offers the host SKU you want. If a SKU isn't available, the portal will show it greyed out or missing in the host SKU picker.

> ⚠️ **Cost warning:** A dedicated host is billed **for the whole physical server, per hour, from the moment it is created**, even if no VMs are running on it. Delete it when you are done (see [Clean Up](#clean-up)).

---

## Step 1: Create a Resource Group

1. Sign in to **https://portal.azure.com**.
2. In the top search bar, type **Resource groups** and select it.
3. Click **+ Create**.
4. Fill in:

   | Field | Value |
   |---|---|
   | Subscription | *your subscription* |
   | Resource group | `rg-dedicatedhost-lab` |
   | Region | `Central India` |

5. Click **Review + create** → **Create**.

✅ **Result:** An empty resource group.

---

## Step 2: Create a Host Group

1. In the top search bar, type **Host groups** and select it.
2. Click **+ Create**.

### Basics tab

| Field | Value | Explanation |
|---|---|---|
| Subscription | *your subscription* | |
| Resource group | `rg-dedicatedhost-lab` | |
| Host group name | `hg-lab-01` | |
| Region | `Central India` | Must match where VMs will live |
| Availability zone | `1` | Optional. If set, every host and VM in this group must be in Zone 1 |
| Fault domain count | `1` | Use `2` or `3` for production HA across racks |
| Support automatic placement of VMs | ☑ (optional) | Lets Azure pick the host for you when you create a VM |
| Support Ultra SSD | ☐ | Only if your VMs need Ultra Disks |

3. Click **Review + create** → **Create**.

> 💡 The **region, zone and fault domain count cannot be changed** after the host group is created. To change them you must create a new host group.

✅ **Result:** A host group with no hosts yet.

---

## Step 3: Create a Dedicated Host

1. Open the host group **hg-lab-01** (or search **Dedicated hosts** → **+ Create**).
2. Click **+ Add host** (or **+ Create** from the Dedicated hosts page).

### Basics tab

| Field | Value | Explanation |
|---|---|---|
| Resource group | `rg-dedicatedhost-lab` | |
| Name | `dh-lab-01` | |
| Location | `Central India` | Filled from the host group |
| Host group | `hg-lab-01` | |
| Size family / SKU | `Dsv3-Type1` | Click **See all sizes** to browse families. This decides which VM sizes fit |
| Fault domain | `0` (or *Automatically assigned*) | Only relevant when the group has >1 FD |
| Automatically replace host on failure | ☑ On | Azure moves your VMs to a healthy host if hardware fails |

### Licensing / Azure Hybrid Benefit (if shown)

- If you own Windows Server / SQL Server licenses with Software Assurance, select the matching option to reduce cost. Otherwise leave as **None**.

### Management tab (optional)

- **Maintenance configuration:** attach one if you want to control when platform updates happen on this host.

3. Click **Review + create** → **Create**. Provisioning usually takes a few minutes.

✅ **Result:** Host **dh-lab-01** shows **Provisioning state: Succeeded** and **Available capacity** listing how many VMs of each size still fit.

> 💡 Check the host's **Overview → Available capacity** before creating VMs. It tells you, for example, how many `Standard_D2s_v3` VMs the host can still hold.

---

## Step 4: Create a Virtual Network

1. Search **Virtual networks** → **+ Create**.
2. **Basics tab:**

   | Field | Value |
   |---|---|
   | Resource group | `rg-dedicatedhost-lab` |
   | Name | `vnet-dh-lab` |
   | Region | `Central India` |

3. **IP addresses tab:**
   - Address space: `10.0.0.0/16`
   - Edit the default subnet (or add one): name `snet-vms`, range `10.0.1.0/24`.
4. **Review + create** → **Create**.

✅ **Result:** A VNet both VMs will share, so they can talk to each other on private IPs.

> You can also skip this step and let the VM wizard create a VNet for VM 1; just make sure VM 2 uses the **same** VNet.

---

## Step 5: Create VM 1 on the Dedicated Host

1. Search **Virtual machines** → **+ Create** → **Azure virtual machine**.

### Basics tab

| Field | Value | Notes |
|---|---|---|
| Resource group | `rg-dedicatedhost-lab` | |
| Virtual machine name | `vm-dh-01` | |
| Region | `Central India` | **Must match** host group |
| Availability options | **Availability zone** | |
| Availability zone | `Zone 1` | **Must match** host group zone |
| Security type | Standard (or Trusted launch if supported by the size) | |
| Image | Ubuntu Server 22.04 LTS / Windows Server 2022 | Any |
| Size | `Standard_D2s_v3` | **Must belong to the host's family** (Dsv3) |
| Authentication | SSH public key (Linux) or Password (Windows) | |
| Username | `azureuser` | |
| Public inbound ports | None (recommended) or SSH/RDP for testing | |

> ⚠️ **Do not choose Spot instances.** Spot VMs are not supported on dedicated hosts.

### Disks tab

- OS disk type: **Premium SSD** or **Standard SSD**. Defaults are fine.

### Networking tab

| Field | Value |
|---|---|
| Virtual network | `vnet-dh-lab` |
| Subnet | `snet-vms (10.0.1.0/24)` |
| Public IP | *(new)* for testing, or **None** if using Bastion |
| NIC network security group | Basic |

### Advanced tab ⭐ (the important part)

Scroll down to the **Host** section:

| Field | Value |
|---|---|
| Host group | `hg-lab-01` |
| Host | `dh-lab-01` *(or "Automatic" if automatic placement is enabled)* |

> If `hg-lab-01` does not appear in the list, the VM's **region, zone or size** doesn't match the host group/host. Go back to **Basics** and fix it.

2. Click **Review + create** → **Create**.

✅ **Result:** `vm-dh-01` is running on `dh-lab-01`.

---

## Step 6: Create VM 2 on the Dedicated Host

Repeat **Step 5** with these differences:

| Field | Value |
|---|---|
| Virtual machine name | `vm-dh-02` |
| Public IP | Optional (you can reach it from VM 1 via private IP) |
| Everything else | **Same** as VM 1, especially region, zone, size family, VNet/subnet, and **Advanced → Host group / Host** |

> 💡 **Shortcut:** On `vm-dh-01`'s Overview, the **Create VM → "More like this"** option (where available) pre-fills most settings. Always re-check the **Advanced → Host** section before creating.

✅ **Result:** Two VMs are now running on the same physical dedicated host.

---

## Step 7: Verify the Setup

### A. From the Dedicated Host

1. Go to **Dedicated hosts → dh-lab-01 → Overview**.
2. Under **Virtual machines** (or the **Virtual machines** blade), you should see:

   | VM | Size | Status |
   |---|---|---|
   | vm-dh-01 | Standard_D2s_v3 | Running |
   | vm-dh-02 | Standard_D2s_v3 | Running |

3. **Available capacity** should have dropped by 2 for that VM size.

### B. From each VM

1. Open **vm-dh-01 → Overview**.
2. In the **Properties** tab, look for **Host group** and **Host**. They should show `hg-lab-01` / `dh-lab-01`.
3. Repeat for **vm-dh-02**.

### C. Connectivity test (optional)

1. Connect to `vm-dh-01` (**Connect → SSH / RDP / Bastion**).
2. Ping or SSH to `vm-dh-02`'s **private IP** (shown on its Overview page):
   ```bash
   ping 10.0.1.5
   ```
   (Replace with the actual private IP. On Windows, allow ICMP in the firewall first.)

---

## Moving an Existing VM onto a Dedicated Host

An existing VM can be moved onto a host if it is in the **same region/zone** and its **size is supported** by the host SKU.

1. Open the VM → **Stop** it and wait until status is **Stopped (deallocated)**.
2. In the VM's **Settings**, open the host setting (shown as **Host** / **Configuration → Host group** depending on portal version).
3. Select the **Host group** and **Host**, then **Save**.
4. **Start** the VM.
5. Confirm on the VM's **Overview → Properties** that the host is set.

> A VM in an **Availability Set** or a **Spot** VM cannot be moved onto a dedicated host this way.

---

## Billing Notes

| Item | Billed? |
|---|---|
| Dedicated host | ✅ Per hour, for the whole host, based on SKU, whether VMs are running or not |
| VM compute (vCPU/RAM) on the host | ❌ Covered by the host charge |
| OS licensing (e.g. Windows Server, SQL Server) | ✅ Separately, unless you apply Azure Hybrid Benefit |
| Managed disks, public IPs, bandwidth | ✅ Separately, as normal |
| Savings | Azure Reservations (1 or 3 years) are available for dedicated hosts |

Check current prices on the **Azure Pricing Calculator** (search "Dedicated Host").

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Host group not listed in VM **Advanced → Host** | Region or zone mismatch | Set VM region/zone to match the host group |
| Host listed but VM size rejected | VM size not in host's family | Pick a size from the host's series (e.g. `Dsv3` host → `D*s_v3` sizes) |
| "Allocation failed" / "insufficient capacity" | Host is full | Check **Available capacity**; add another host to the group |
| Quota error when creating host | Not enough vCPU quota for the host family | **Usage + quotas → Request increase** |
| Host SKU missing from the picker | SKU not offered in that region/zone | Try another region, zone or host family |
| Can't delete host | VMs still assigned to it | Delete or move all VMs first |
| Can't delete host group | Hosts still inside it | Delete all hosts first |

---

## Clean Up

Resources must be removed **in this order** because of dependencies:

1. **Delete VMs**: `vm-dh-01`, `vm-dh-02` (and their disks / NICs / public IPs if not auto-deleted).
2. **Delete the dedicated host**: `dh-lab-01`. *This stops the host billing.*
3. **Delete the host group**: `hg-lab-01`.

**Fastest option:** delete the whole resource group:

1. Go to **Resource groups → rg-dedicatedhost-lab**.
2. Click **Delete resource group**.
3. Type the resource group name to confirm → **Delete**.

> Azure handles the dependency order automatically when you delete the resource group.

---

## Quick Reference Checklist

```
[ ] Subscription type supports Dedicated Host (not free trial)
[ ] vCPU quota available for host family in region
[ ] Resource group created
[ ] Host group created  (region + zone + fault domains)
[ ] Dedicated host created  (SKU family chosen, auto-replace ON)
[ ] VNet + subnet created
[ ] VM 1 created  → same region/zone, matching size, Advanced → Host set
[ ] VM 2 created  → same as above, same VNet
[ ] Verified both VMs appear under the host
[ ] Clean up when done (VMs → Host → Host group)
```

---

### Golden Rules

1. **Region and zone** of the VM must match the **host group**.
2. **VM size series** must match the **host SKU family**.
3. **No Spot VMs** on dedicated hosts.
4. The host is **billed as a whole**, so delete it when not needed.

---

*Portal labels may shift slightly as Azure updates its UI; the field names above match the standard VM and Dedicated Host creation wizards.*
