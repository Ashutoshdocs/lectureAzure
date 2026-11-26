# Azure Virtual Desktop (AVD): Portal Setup & Access Guide for 2 Users

This guide explains, **step by step through the Azure portal UI**, how to deploy Azure Virtual Desktop and give **two users** (`user1` and `user2`) access to a shared Windows desktop. It also explains how each user signs in and connects.

> **Audience:** Azure administrators (setup) and end users (access).
> **Approach:** Azure portal only. No CLI or PowerShell required.

---

## Table of Contents

1. [What is Azure Virtual Desktop?](#1-what-is-azure-virtual-desktop)
2. [Architecture Overview](#2-architecture-overview)
3. [Prerequisites](#3-prerequisites)
4. [Admin Setup in the Azure Portal](#4-admin-setup-in-the-azure-portal)
   - [Step 1: Create the two users](#step-1-create-the-two-users-in-microsoft-entra-id)
   - [Step 2: Create a resource group](#step-2-create-a-resource-group)
   - [Step 3: Create a virtual network](#step-3-create-a-virtual-network)
   - [Step 4: Create the host pool and session host](#step-4-create-the-host-pool-and-session-host)
   - [Step 5: Assign the users to the desktop](#step-5-assign-the-two-users-to-the-desktop-application-group)
   - [Step 6: Grant VM sign-in permission](#step-6-grant-vm-sign-in-permission-entra-joined-vms)
   - [Step 7: Configure RDP properties](#step-7-configure-rdp-properties)
5. [How Users Access AVD](#5-how-users-access-avd)
   - [Option A: Web browser](#option-a-web-browser-no-install)
   - [Option B: Windows App](#option-b-windows-app-desktop--mobile)
6. [Two-User Scenario Walkthrough](#6-two-user-scenario-walkthrough)
7. [Verify & Monitor Sessions](#7-verify--monitor-sessions)
8. [Cost-Saving Tips](#8-cost-saving-tips)
9. [Troubleshooting](#9-troubleshooting)
10. [Clean Up](#10-clean-up)

---

## 1. What is Azure Virtual Desktop?

Azure Virtual Desktop is a Microsoft service that runs Windows desktops and apps in Azure. Users connect from any device (Windows, macOS, iOS, Android or a web browser) and get a full Windows experience while the data and compute stay in the cloud.

**Key components**

| Component | What it is |
|---|---|
| **Host pool** | A group of identical VMs (session hosts) that serve desktops |
| **Session host** | A Windows VM that users actually sign in to |
| **Application group** | Defines what users get: a full **Desktop** or individual **RemoteApps** |
| **Workspace** | The container users see in their client; it lists the app groups |
| **Users / groups** | Microsoft Entra ID identities assigned to the application group |

---

## 2. Architecture Overview

```
                ┌───────────────────────────────────────────────┐
                │              Microsoft Entra ID               │
                │      user1@contoso.com   user2@contoso.com    │
                └──────────────────────┬────────────────────────┘
                                       │ sign-in / MFA
        ┌──────────────┐               ▼
        │   user1      │     ┌───────────────────────┐
        │ (Web browser)├────►│  Workspace: ws-avd    │
        └──────────────┘     │  (AVD control plane)  │
        ┌──────────────┐     └──────────┬────────────┘
        │   user2      ├────►           │
        │ (Windows App)│                ▼
        └──────────────┘     ┌───────────────────────┐
                             │ App group: Desktop    │
                             │ (user1, user2 assigned)│
                             └──────────┬────────────┘
                                        ▼
                ┌───────────────────────────────────────────┐
                │ Host pool: hp-avd-pooled (Pooled, max 2)  │
                │  ┌─────────────────────────────────────┐  │
                │  │ Session host VM: avd-sh-0           │  │
                │  │ Windows 11 Enterprise multi-session │  │
                │  │  ├─ Session: user1                  │  │
                │  │  └─ Session: user2                  │  │
                │  └─────────────────────────────────────┘  │
                │         VNet: vnet-avd / snet-avd         │
                └───────────────────────────────────────────┘
```

Both users share **one multi-session VM**, each with their own isolated Windows session and profile.

---

## 3. Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | With permission to create resources (Owner or Contributor + User Access Administrator) |
| Microsoft Entra ID | Tenant where the two user accounts live |
| Licensing | Each user needs an eligible license, e.g. Microsoft 365 E3/E5/A3/A5/Business Premium or Windows Enterprise E3/E5 |
| Region | Pick one close to the users (e.g. **Central India** for users in India) |
| VM quota | Enough vCPU quota in that region for the VM size you choose |

---

## 4. Admin Setup in the Azure Portal

Sign in at **https://portal.azure.com**.

### Step 1: Create the two users in Microsoft Entra ID

> Skip this step if the users already exist.

1. In the portal search bar, type **Microsoft Entra ID** and open it.
2. Go to **Manage → Users → + New user → Create new user**.
3. Fill in:
   - **User principal name:** `user1@<yourdomain>`
   - **Display name:** `User One`
   - **Password:** auto-generate (copy it) or set one
4. Click **Review + create → Create**.
5. Repeat for `user2@<yourdomain>` / `User Two`.
6. *(Recommended)* Create a group so permissions are managed in one place:
   - **Groups → + New group**
   - **Group type:** Security, **Name:** `AVD-Users`
   - **Members:** add `user1` and `user2` → **Create**

> Make sure both users have an eligible license assigned (**Users → select user → Licenses**).

---

### Step 2: Create a resource group

1. Search **Resource groups** → **+ Create**.
2. **Subscription:** your subscription
3. **Resource group:** `rg-avd-demo`
4. **Region:** e.g. `Central India`
5. **Review + create → Create**.

---

### Step 3: Create a virtual network

1. Search **Virtual networks** → **+ Create**.
2. **Basics** tab:
   - **Resource group:** `rg-avd-demo`
   - **Name:** `vnet-avd`
   - **Region:** same as the resource group
3. **IP addresses** tab:
   - Address space: `10.0.0.0/16`
   - Edit the default subnet → **Name:** `snet-avd`, range `10.0.1.0/24`
4. **Review + create → Create**.

> The session host does **not** need a public IP. AVD uses a reverse-connect transport, so no inbound RDP port needs to be opened.

---

### Step 4: Create the host pool and session host

The host pool wizard creates the host pool, VM, workspace and desktop app group together.

1. Search **Azure Virtual Desktop** and open it.
2. Click **Host pools → + Create**.

#### Basics tab

| Field | Value |
|---|---|
| Resource group | `rg-avd-demo` |
| Host pool name | `hp-avd-pooled` |
| Location | `Central India` (metadata location) |
| Validation environment | No |
| Preferred app group type | **Desktop** |
| Host pool type | **Pooled** |
| Load balancing algorithm | **Breadth-first** |
| Max session limit | **2** |

Click **Next: Virtual Machines**.

#### Virtual Machines tab

| Field | Value |
|---|---|
| Add Azure virtual machines | **Yes** |
| Resource group | `rg-avd-demo` |
| Name prefix | `avd-sh` |
| Virtual machine location | `Central India` |
| Availability options | No infrastructure redundancy required |
| Security type | Trusted launch virtual machines |
| Image | **Windows 11 Enterprise multi-session** (latest, optionally with Microsoft 365 Apps) |
| Virtual machine size | e.g. `Standard_D2s_v5` (2 vCPU, 8 GB) – fine for 2 light users; use D4s_v5 for heavier work |
| Number of VMs | **1** |
| OS disk type | Standard SSD or Premium SSD |
| Virtual network | `vnet-avd` |
| Subnet | `snet-avd` |
| Network security group | Basic |
| Public inbound ports | **No** |
| Select which directory you would like to join | **Microsoft Entra ID** |
| Enroll VM with Intune | Optional |
| Virtual machine administrator account | Set a local admin username and password (store safely) |

Click **Next: Workspace**.

#### Workspace tab

| Field | Value |
|---|---|
| Register desktop app group | **Yes** |
| To this workspace | **Create new** → `ws-avd` |

Click **Review + create → Create**. Deployment takes roughly 10–20 minutes.

When it finishes you will have:

- Host pool `hp-avd-pooled`
- Session host VM `avd-sh-0`
- Application group `hp-avd-pooled-DAG` (Desktop)
- Workspace `ws-avd`

---

### Step 5: Assign the two users to the desktop application group

1. In **Azure Virtual Desktop → Application groups**, open **`hp-avd-pooled-DAG`**.
2. Go to **Manage → Assignments → + Add**.
3. Search and select **`AVD-Users`** (or `user1` and `user2` individually).
4. Click **Select**.

This gives both users the **Desktop Virtualization User** role on the app group, which makes the desktop appear in their client.

> *(Optional)* Rename the desktop users see: **Application groups → hp-avd-pooled-DAG → Applications → SessionDesktop** → set **Display name** to e.g. `Company Desktop`.

---

### Step 6: Grant VM sign-in permission (Entra-joined VMs)

Because the session host is joined to Microsoft Entra ID, users also need permission to sign in to the VM itself.

1. Open **Resource groups → `rg-avd-demo`**.
2. Go to **Access control (IAM) → + Add → Add role assignment**.
3. **Role** tab: search and select **Virtual Machine User Login**.
   (Use **Virtual Machine Administrator Login** only for admins.)
4. **Members** tab: **+ Select members** → choose `AVD-Users` → **Select**.
5. **Review + assign**.

> Without this role, users see the desktop icon but sign-in to the session fails.

---

### Step 7: Configure RDP properties

1. Open **Host pools → `hp-avd-pooled` → Settings → RDP Properties**.
2. **Connection information** tab:
   - **Microsoft Entra single sign-on:** *Connections will use Microsoft Entra authentication to provide single sign-on* (recommended).
3. **Advanced** tab: make sure the RDP string includes:

   ```
   targetisaadjoined:i:1;enablerdsaadauth:i:1;
   ```

   `targetisaadjoined:i:1` lets users connect from the web or from devices that are not joined to the same Entra tenant.
4. *(Optional)* **Device redirection** tab: allow or block clipboard, drives, printers, camera, microphone as your policy requires.
5. Click **Save**.

✅ **Setup is complete.** Both users can now connect.

---

## 5. How Users Access AVD

Share this section with `user1` and `user2`.

### Option A: Web browser (no install)

Works on any modern browser (Edge, Chrome, Safari, Firefox).

1. Open **https://windows.cloud.microsoft**
2. Sign in with your work account (e.g. `user1@<yourdomain>`) and complete MFA if prompted.
3. On the **Devices** / home page, find **Company Desktop** (or *SessionDesktop*) under workspace `ws-avd`.
4. Click **Connect**.
5. Choose which local resources to allow (clipboard, printer, etc.) → **Connect**.
6. Sign in again if prompted. Your Windows desktop opens in the browser tab.

> 💡 Press **F11** for full-screen. Use the toolbar at the top to disconnect.

### Option B: Windows App (desktop & mobile)

Microsoft's **Windows App** is the recommended client for the best performance (multi-monitor, Teams optimization, device redirection).

| Platform | Where to get it |
|---|---|
| Windows | Microsoft Store → search **Windows App** |
| macOS | Mac App Store → **Windows App** |
| iOS / iPadOS | App Store → **Windows App** |
| Android | Google Play → **Windows App** |

**Steps**

1. Install and open **Windows App**.
2. Click **Sign in** and enter your work account.
3. The workspace **ws-avd** appears with the **Company Desktop** tile.
4. Click / tap the tile to connect.
5. *(Optional)* Pin it to **Favorites** for one-click access next time.

### Ending your session

| Action | What happens |
|---|---|
| **Sign out** (Start → user icon → Sign out) | Closes apps and ends the session. Frees the slot. **Recommended when done.** |
| **Disconnect** (close the window / tab) | Session keeps running; apps stay open and you can reconnect later. Still counts toward the 2-session limit. |

---

## 6. Two-User Scenario Walkthrough

| | **user1** | **user2** |
|---|---|---|
| Account | `user1@<yourdomain>` | `user2@<yourdomain>` |
| Client | Web browser on a laptop | Windows App on Windows / macOS |
| Connects to | Company Desktop → `avd-sh-0` | Company Desktop → `avd-sh-0` |
| Session | Session 1 (own profile, own files) | Session 2 (own profile, own files) |
| Can see the other user's files? | ❌ No | ❌ No |

**What happens step by step**

1. **user1** opens the browser, signs in, clicks **Company Desktop** → the broker places them on `avd-sh-0` (session 1 of 2).
2. **user2** opens Windows App, signs in, clicks **Company Desktop** → placed on the same VM (session 2 of 2).
3. Both work at the same time, each in a separate Windows session.
4. If a **third** user were assigned, they would be refused because the host pool limit is 2 sessions on 1 VM. Add another VM or raise the limit to support more users.

> **Profiles:** By default each user gets a local profile on the VM. If you add more session hosts later, set up **FSLogix** profile containers on Azure Files so profiles follow users between VMs.

---

## 7. Verify & Monitor Sessions

**Check the session host is healthy**

- **Host pools → hp-avd-pooled → Session hosts**
- `avd-sh-0` should show **Status: Available** and **Allow new sessions: Yes**.

**See who is connected**

- **Host pools → hp-avd-pooled → Session hosts → avd-sh-0 → Active sessions** (or the **User sessions** blade)
- You should see `user1` and `user2` with **Active** or **Disconnected** state.
- From here an admin can **Send message**, **Disconnect** or **Log off** a user.

**Insights (optional)**

- **Azure Virtual Desktop → Insights** shows connection reliability, latency and usage once diagnostics are sent to a Log Analytics workspace (**Host pool → Diagnostic settings**).

---

## 8. Cost-Saving Tips

| Tip | Where in the portal |
|---|---|
| **Start VM on Connect**: VM boots automatically when a user connects, so it can stay off when idle | Host pool → **Properties** → *Start VM on connect: Yes* (requires the Azure Virtual Desktop service principal to have the **Desktop Virtualization Power On Contributor** role on the subscription or resource group) |
| **Scaling plan**: power off VMs outside working hours | Azure Virtual Desktop → **Scaling plans → + Create** → assign to `hp-avd-pooled` |
| **Auto-shutdown** | VM → **Operations → Auto-shutdown** |
| **Session time limits**: log off idle/disconnected sessions | Group Policy / Intune settings on the session host |
| Right-size the VM | VM → **Size** |

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| User sees **no desktop** after sign-in | Not assigned to the app group | Step 5: add the user/group under **Assignments** |
| Desktop appears but sign-in **fails / access denied** | Missing VM login role | Step 6: assign **Virtual Machine User Login** |
| *"The sign-in method you're trying to use isn't allowed"* from web or a personal device | RDP property missing | Step 7: add `targetisaadjoined:i:1` |
| *"No resources available"* / cannot connect | VM stopped, unavailable, or session limit reached | Start the VM, check **Session hosts** status, sign out unused sessions, or raise **Max session limit** |
| Session host shows **Unavailable** | AVD agent issue or VM not running | Restart the VM; check **Session hosts → Health details** |
| Repeated MFA / credential prompts | SSO not enabled | Step 7: enable Microsoft Entra single sign-on |
| Slow or laggy session | Distant region or small VM | Choose a closer region; increase VM size |

---

## 10. Clean Up

To remove everything created in this guide and stop all charges:

1. Go to **Resource groups → `rg-avd-demo`**.
2. Click **Delete resource group**.
3. Type the resource group name to confirm → **Delete**.

> The Entra ID users and the `AVD-Users` group are not deleted with the resource group. Remove them separately in **Microsoft Entra ID** if no longer needed.

---

## Quick Reference

| Item | Value |
|---|---|
| Azure portal | https://portal.azure.com |
| Web client | https://windows.cloud.microsoft |
| Client app | Windows App (Store / App Store / Google Play) |
| Resource group | `rg-avd-demo` |
| Host pool | `hp-avd-pooled` (Pooled, Breadth-first, max 2 sessions) |
| Session host | `avd-sh-0` (Windows 11 Enterprise multi-session) |
| App group | `hp-avd-pooled-DAG` (Desktop) |
| Workspace | `ws-avd` |
| User group | `AVD-Users` → `user1`, `user2` |
| Required user roles | Desktop Virtualization User (app group) + Virtual Machine User Login (resource group) |
