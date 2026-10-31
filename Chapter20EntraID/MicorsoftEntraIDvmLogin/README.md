# Azure Windows VM with Microsoft Entra ID Login (Portal Guide)

This guide uses the **Azure portal UI only**. It walks through:

1. Creating a Windows VM in Azure
2. Enabling Microsoft Entra ID login on the VM
3. Creating a Microsoft Entra ID user
4. Giving that user a role that allows VM sign-in
5. Signing in to the VM over RDP as that user

---

## Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | You need **Owner** or **User Access Administrator** + **Contributor** on the subscription or resource group (to create the VM and assign roles). |
| Entra ID permissions | **User Administrator** (or higher) in Microsoft Entra ID to create users. |
| Supported VM OS | Windows Server 2019 or later, or Windows 10 (20H2+) / Windows 11. |
| Client machine | A Windows 10/11 PC with the Remote Desktop client (`mstsc`). |
| Network | Outbound from the VM to `login.microsoftonline.com`, `pas.windows.net`, `enterpriseregistration.windows.net`, and `device.login.microsoftonline.com` (allowed by default). Inbound RDP (TCP 3389) from your IP, or Azure Bastion. |

---

## Step 1 — Create the Windows VM

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Search for **Virtual machines** → **+ Create** → **Azure virtual machine**.
3. **Basics** tab:
   - **Subscription**: select yours
   - **Resource group**: **Create new** → e.g. `rg-entra-vm-demo`
   - **Virtual machine name**: e.g. `vm-entra-win01`
   - **Region**: choose the closest region
   - **Availability options**: *No infrastructure redundancy required* (fine for a demo)
   - **Security type**: *Trusted launch virtual machines*
   - **Image**: *Windows Server 2022 Datacenter: Azure Edition* (or Windows 11)
   - **Size**: e.g. `Standard_B2s` or `Standard_D2s_v5`
   - **Administrator account**: enter a local admin **username** and a strong **password** (keep these as a break-glass account)
   - **Inbound port rules**: *Allow selected ports* → **RDP (3389)**
     > For production, choose *None* and use Azure Bastion or restrict the NSG rule to your own IP after creation.
4. **Disks** tab: leave defaults (*Premium SSD* or *Standard SSD*).
5. **Networking** tab: leave defaults (new VNet, subnet, and public IP are created).
6. **Management** tab — **this is where Entra ID login is enabled**:
   - Under **Identity**, tick **Enable system assigned managed identity**
   - Under **Microsoft Entra ID**, tick **Login with Microsoft Entra ID**
     > Ticking this installs the `AADLoginForWindows` extension automatically during deployment. If you do this here, you can skip Step 2.
7. Click **Review + create** → wait for validation → **Create**.
8. Wait for **Your deployment is complete**, then click **Go to resource**.

---

## Step 2 — Enable Microsoft Entra ID Login (if not done during creation)

Skip this step if you ticked **Login with Microsoft Entra ID** in Step 1.

### 2a. Turn on the system-assigned managed identity

1. Open the VM → **Security** → **Identity** (in some portal layouts: **Settings** → **Identity**).
2. On the **System assigned** tab, set **Status** to **On** → **Save** → **Yes**.

### 2b. Install the Entra ID login extension

1. Open the VM → **Settings** → **Extensions + applications**.
2. Click **+ Add**.
3. Search for **Azure AD based Windows Login** (publisher: Microsoft Corp., type `AADLoginForWindows`).
4. Select it → **Next** → **Review + create** → **Create**.
5. Wait until the extension status shows **Provisioning succeeded**.

### 2c. Confirm

On the **Extensions + applications** page you should see:

| Name | Type | Status |
|---|---|---|
| AADLoginForWindows | Microsoft.Azure.ActiveDirectory.AADLoginForWindows | Provisioning succeeded |

---

## Step 3 — Create a Microsoft Entra ID User

1. In the portal search bar, open **Microsoft Entra ID**.
2. Go to **Manage** → **Users** → **+ New user** → **Create new user**.
3. **Basics** tab:
   - **User principal name**: e.g. `vmuser01` @ `yourtenant.onmicrosoft.com`
   - **Display name**: e.g. `VM User 01`
   - **Password**: leave **Auto-generate password** ticked and **copy the password** shown (or untick and set your own)
   - **Account enabled**: ticked
4. (Optional) **Properties** tab: fill in job title, department, usage location, etc.
5. Click **Review + create** → **Create**.

> The user must change the password at first sign-in. The easiest way is to sign in once at <https://portal.azure.com> or <https://myaccount.microsoft.com> with the temporary password and set a new one **before** trying RDP.

---

## Step 4 — Assign a VM Login Role to the User

Entra ID users can only sign in to the VM if they hold one of these Azure RBAC roles:

| Role | What it allows |
|---|---|
| **Virtual Machine Administrator Login** | Sign in with **local administrator** rights |
| **Virtual Machine User Login** | Sign in as a **standard user** |

> Owner/Contributor roles alone do **not** grant RDP sign-in rights.

1. Open the VM (`vm-entra-win01`).
2. Select **Access control (IAM)**.
3. Click **+ Add** → **Add role assignment**.
4. **Role** tab: search for and select **Virtual Machine Administrator Login** (or **Virtual Machine User Login**) → **Next**.
5. **Members** tab:
   - **Assign access to**: *User, group, or service principal*
   - Click **+ Select members** → search for `vmuser01` → **Select**
6. Click **Review + assign** → **Review + assign**.
7. Verify: **Access control (IAM)** → **Role assignments** shows `VM User 01` with the chosen role.

> **Tip:** You can assign the role at the **resource group** or **subscription** level instead, so the user can sign in to every VM within that scope. For many users, assign the role to an **Entra ID group** rather than to individuals.

Role assignments can take **up to a few minutes** to take effect.

---

## Step 5 — Sign In to the VM as the Entra ID User

### 5a. Get the RDP file

1. Open the VM → **Connect** → **Connect** (or **Native RDP** → **Select**).
2. Choose **Public IP address**, port **3389**.
3. Click **Download RDP file**.

### 5b. Connect using web account sign-in (recommended)

This method works from **any** Windows 10/11 client (the client does **not** need to be joined to Entra ID) and supports MFA and Conditional Access.

1. **Right-click** the downloaded `.rdp` file → **Edit** (opens `mstsc`).
2. Go to the **Advanced** tab.
3. Tick **Use a web account to sign in to the remote computer**.
4. Return to the **General** tab → **Connect**.
5. A Microsoft sign-in window appears. Enter:
   - **Username**: `vmuser01@yourtenant.onmicrosoft.com`
   - **Password**: the user's new password
   - Complete MFA if prompted
6. If asked **"Allow remote desktop connection?"**, click **Yes**.
7. You are now signed in to the VM as the Entra ID user.

> If you'll connect often, open the `.rdp` file in Notepad and confirm it contains `enablerdsaadauth:i:1` — that's the setting the checkbox adds.

### 5c. Alternative: legacy method (Entra-joined client only)

Use this only if your **local PC is Entra ID joined / hybrid joined / registered to the same tenant** and no MFA is enforced for the sign-in:

1. Open the `.rdp` file normally (don't tick the web account option).
2. Choose **More choices** → **Use a different account**.
3. Username: `AzureAD\vmuser01@yourtenant.onmicrosoft.com`
4. Enter the password → **OK**.

---

## Step 6 — Verify the Sign-In on the VM

Inside the VM, open **Command Prompt** and run:

```cmd
whoami
```

Expected output similar to:

```
azuread\vmuser01
```

Check that the VM is joined to Entra ID:

```cmd
dsregcmd /status
```

Look for:

```
AzureAdJoined : YES
```

If the user has **Virtual Machine Administrator Login**, confirm admin rights:

```cmd
net localgroup administrators
```

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| **"The sign-in method you're trying to use isn't allowed"** | The user doesn't have a VM login role. Recheck Step 4 and wait a few minutes. |
| **"Your credentials did not work"** | Wrong username format. With web account sign-in use `user@domain`; with legacy method use `AzureAD\user@domain`. Make sure the temporary password was already changed. |
| **"Your account is configured to prevent you from using this device"** | User has neither VM login role, or role was assigned at the wrong scope. |
| **"The logon attempt failed"** with MFA enabled | Legacy method doesn't support MFA. Use **web account sign-in** (Step 5b). |
| **Extension shows "Provisioning failed"** | The VM can't reach Entra ID endpoints, or managed identity is off. Check NSG/firewall outbound rules and Step 2a, then reinstall the extension. |
| **`AzureAdJoined : NO`** | Extension didn't finish. Restart the VM and check **Extensions + applications**. Logs are in `C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\`. |
| **Can't reach port 3389** | NSG has no inbound RDP rule for your IP. VM → **Networking** → **Network settings** → add an inbound rule for TCP 3389 from your IP, or use Azure Bastion. |

---

## Security Recommendations

- Restrict inbound RDP to your own IP, or remove it and use **Azure Bastion**.
- Prefer **Virtual Machine User Login** unless admin rights are truly needed.
- Assign roles to **Entra ID groups**, not individual users.
- Enforce **MFA** with a Conditional Access policy targeting the **Azure Windows VM Sign-In** app.
- Keep the local admin account from Step 1 as a break-glass account with a strong, vaulted password.

---

## Clean Up

To avoid ongoing charges when you're done:

1. Portal → **Resource groups** → `rg-entra-vm-demo` → **Delete resource group**.
2. Type the resource group name to confirm → **Delete**.
3. (Optional) **Microsoft Entra ID** → **Users** → select `vmuser01` → **Delete**.

---

## Reference

- [Sign in to a Windows VM in Azure by using Microsoft Entra ID](https://learn.microsoft.com/entra/identity/devices/howto-vm-sign-in-azure-ad-windows)
- [Assign Azure roles using the Azure portal](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal)
- [Create a Windows VM in the Azure portal](https://learn.microsoft.com/azure/virtual-machines/windows/quick-create-portal)
