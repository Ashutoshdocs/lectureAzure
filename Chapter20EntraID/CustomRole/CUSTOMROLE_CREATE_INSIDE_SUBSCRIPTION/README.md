# Demo: Azure Custom Role — "Start VM Only Role" (Portal Guide)

This demo uses the **Azure portal UI** to create a custom role that lets a user **start** a VM but **not stop** it, assign it to a new user, and prove it works.

| Action | Allowed? |
|---|---|
| View the VM | ✅ Yes |
| Start the VM | ✅ Yes |
| Stop (deallocate) the VM | ❌ No |
| Restart the VM | ❌ No |
| Delete / resize / change the VM | ❌ No |

---

## The role definition

File: `start-vm-only-role.json`

```json
{
  "properties": {
    "roleName": "Start VM Only Role",
    "description": "Can start VM but cannot stop it",
    "assignableScopes": [
      "/subscriptions/6f787beb-8095-4923-ae3e-deba86057045"
    ],
    "permissions": [
      {
        "actions": [
          "Microsoft.Compute/virtualMachines/read",
          "Microsoft.Compute/virtualMachines/start/action"
        ],
        "notActions": [
          "Microsoft.Compute/virtualMachines/deallocate/action"
        ],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

### What each part does

| Field | Meaning |
|---|---|
| `roleName` | Name shown in the portal when assigning the role |
| `assignableScopes` | The role can be assigned anywhere inside this subscription (subscription, resource group, or a single VM) |
| `virtualMachines/read` | See the VM in the portal |
| `virtualMachines/start/action` | Use the **Start** button |
| `notActions: deallocate/action` | Explicitly excludes deallocate (the portal **Stop** button) |

> **Good to know:** `notActions` is **not a deny**. It only removes permissions from the `actions` of the same role. Here `deallocate/action` was never granted anyway, so the user can't stop the VM either way. The line is useful as documentation. If the user also has another role (e.g. Contributor or Virtual Machine Contributor) at any scope covering the VM, they **will** be able to stop it, because RBAC permissions add up.

---

## Demo values used in this guide

| Item | Value |
|---|---|
| Subscription ID | `6f787beb-8095-4923-ae3e-deba86057045` |
| Resource group | `rg-startonly-demo` |
| VM name | `vm-startonly01` |
| Demo user | `vmstarter01@<yourtenant>.onmicrosoft.com` |
| Custom role | `Start VM Only Role` |

---

## Prerequisites

- **Owner** or **User Access Administrator** on subscription `6f787beb-8095-4923-ae3e-deba86057045` (to create the custom role and assign it).
- **Contributor** or higher to create the VM.
- **User Administrator** (or higher) in Microsoft Entra ID to create the user.
- An **InPrivate / Incognito** browser window for signing in as the demo user.

---

## Step 1 — Create the resource group

1. Sign in to the [Azure portal](https://portal.azure.com) as admin.
2. Search **Resource groups** → **+ Create**.
3. **Subscription**: the one above · **Resource group**: `rg-startonly-demo` · **Region**: your choice.
4. **Review + create** → **Create**.

---

## Step 2 — Create the VM

1. Search **Virtual machines** → **+ Create** → **Azure virtual machine**.
2. **Basics** tab:
   - **Resource group**: `rg-startonly-demo`
   - **Virtual machine name**: `vm-startonly01`
   - **Image**: *Windows Server 2022 Datacenter: Azure Edition* (or Ubuntu)
   - **Size**: a small size such as `Standard_B2s`
   - **Administrator account**: set a username and strong password
   - **Inbound port rules**: *None* (no RDP/SSH needed for this demo)
3. Leave other tabs at defaults → **Review + create** → **Create**.
4. When deployment finishes, click **Go to resource**.
5. **Stop the VM now as admin**: **Overview** → **Stop** → **Yes**. Wait until **Status** shows **Stopped (deallocated)**. This sets up Test 1.

---

## Step 3 — Create the demo user

1. Search **Microsoft Entra ID** → **Manage** → **Users** → **+ New user** → **Create new user**.
2. **User principal name**: `vmstarter01` · **Display name**: `VM Starter 01`.
3. Leave **Auto-generate password** ticked and **copy the password**.
4. **Review + create** → **Create**.

---

## Step 4 — Create the custom role from JSON

Because `assignableScopes` is the subscription, create the role from the **subscription's** IAM page.

1. Save the JSON above as `start-vm-only-role.json` on your computer (or use the file provided).
2. In the portal, search **Subscriptions** → select subscription `6f787beb-8095-4923-ae3e-deba86057045`.
3. Open **Access control (IAM)** → **+ Add** → **Add custom role**.
4. **Basics** tab:
   - **Baseline permissions**: select **Start from JSON**
   - **File**: browse to and upload `start-vm-only-role.json`
   - Confirm **Custom role name** = `Start VM Only Role` and **Description** = `Can start VM but cannot stop it`
5. **Permissions** tab: confirm you see
   - `Microsoft.Compute/virtualMachines/read` — Permission
   - `Microsoft.Compute/virtualMachines/start/action` — Permission
   - `Microsoft.Compute/virtualMachines/deallocate/action` — **NotAction**
6. **Assignable scopes** tab: confirm `/subscriptions/6f787beb-8095-4923-ae3e-deba86057045`.
7. **JSON** tab: review the final JSON.
8. **Review + create** → **Create**.
9. Verify: **Access control (IAM)** → **Roles** tab → set **Type** filter to **CustomRole** → `Start VM Only Role` appears.

> A newly created custom role can take a few minutes to appear in role-assignment pickers.

---

## Step 5 — Assign the role to the user

Assign it to just the demo VM (least privilege). You could also assign at the resource group or subscription.

1. Open **Virtual machines** → `vm-startonly01` → **Access control (IAM)**.
2. **+ Add** → **Add role assignment**.
3. **Role** tab: search `Start VM Only Role` (switch to the **Job function roles** tab if needed) → select it → **Next**.
4. **Members** tab:
   - **Assign access to**: *User, group, or service principal*
   - **+ Select members** → search `vmstarter01` → **Select**
5. **Review + assign** → **Review + assign**.
6. Verify: **Access control (IAM)** → **Role assignments** shows `VM Starter 01` — `Start VM Only Role` — scope *This resource*.

Wait **about 5 minutes** for the assignment to take effect.

---

## Step 6 — Sign in as the demo user

1. Open an **InPrivate / Incognito** window.
2. Go to <https://portal.azure.com>.
3. Sign in as `vmstarter01@<yourtenant>.onmicrosoft.com` with the temporary password.
4. Set a new password when prompted.
5. Search **Virtual machines** → open `vm-startonly01`.

> If the VM list is empty, click the gear icon → **Directories + subscriptions** and make sure the subscription is selected. You can also search the VM name directly in the top search bar.

---

## Step 7 — Prove the role works

Run every test as `vmstarter01`.

### Test 1 — Start the VM ✅

1. VM **Overview** → **Start**.
2. **Expected**: notification *"Starting virtual machine…"* then *"Successfully started virtual machine"*.
3. Refresh the page: **Status** = **Running**.

### Test 2 — Stop the VM ❌

1. VM **Overview** → **Stop** → **Yes**.
2. **Expected**: failure notification similar to:

   ```
   Failed to stop virtual machine 'vm-startonly01'.
   Error: The client 'vmstarter01@<yourtenant>.onmicrosoft.com' with object id '...'
   does not have authorization to perform action
   'Microsoft.Compute/virtualMachines/deallocate/action' over scope
   '/subscriptions/6f787beb-.../resourceGroups/rg-startonly-demo/providers/Microsoft.Compute/virtualMachines/vm-startonly01'
   or the scope is invalid.
   ```

3. Refresh: **Status** is still **Running**.

### Test 3 — Restart the VM ❌

1. VM **Overview** → **Restart** → **Yes**.
2. **Expected**: authorization failure for `Microsoft.Compute/virtualMachines/restart/action`.

### Test 4 — Change the VM ❌ (bonus)

1. VM → **Size** → pick another size → **Resize**, or VM → **Delete**.
2. **Expected**: authorization failure for `virtualMachines/write` or `virtualMachines/delete`.

> The portal may grey out some buttons or show *"You don't have permission"* banners before you even click. That is also proof the role is working.

### Collect the evidence (admin)

1. As admin, open `vm-startonly01` → **Activity log**.
2. Set **Timespan** to *Last hour* and filter **Event initiated by** = `vmstarter01`.
3. You'll see:

| Operation | Status |
|---|---|
| Start Virtual Machine | Succeeded |
| Deallocate Virtual Machine | Failed |
| Restart Virtual Machine | Failed |

4. Click a failed event → **JSON** tab to capture the `AuthorizationFailed` message.

### Results checklist

| Test | Expected | Your result |
|---|---|---|
| 1. Start | Succeeds | |
| 2. Stop | Fails — AuthorizationFailed (`deallocate/action`) | |
| 3. Restart | Fails — AuthorizationFailed (`restart/action`) | |
| 4. Resize / delete | Fails — AuthorizationFailed | |

---

## Notes and limitations

- **Portal status display.** With only `virtualMachines/read`, some portal views may show the VM status as *Unknown* or prompt that you lack permission to see details. Starting still works. If you want status to display cleanly, add `Microsoft.Compute/virtualMachines/instanceView/read` to `actions`.
- **powerOff isn't listed but is still blocked.** `Microsoft.Compute/virtualMachines/powerOff/action` (stop without deallocating, used by CLI/PowerShell `--skip-shutdown`/`-StayProvisioned`) was never granted, so it's blocked too. Add it to `notActions` if you want the intent documented.
- **Stopping from inside the VM.** A user who can sign in to the guest OS (RDP/SSH) can shut it down from Windows or Linux. This role grants no VM login, so that isn't possible here; keep it that way if stopping must be fully prevented.
- **Other roles override.** RBAC is additive. Make sure the demo user has no other role (e.g. Contributor) at the VM, resource group, subscription, or management group.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Upload fails: *assignable scope not valid* | You're creating the role from a resource group IAM page; create it from the **subscription's** IAM page, or confirm you're Owner on that subscription. |
| Role not found when assigning | Wait a few minutes after creating it and refresh. |
| User can't see the VM | Wait ~5 min after assignment; check subscription filter in portal settings. |
| User **can** stop the VM | The user has another role granting it. Check **Access control (IAM)** → **Check access** → search the user → review all assignments. |
| Start fails with AuthorizationFailed | Role assignment hasn't propagated yet, or was assigned to the wrong VM/user. |

---

## Clean up

1. VM `vm-startonly01` → **Access control (IAM)** → **Role assignments** → remove `VM Starter 01`.
2. **Resource groups** → `rg-startonly-demo` → **Delete resource group** → type the name → **Delete**.
3. **Subscriptions** → your subscription → **Access control (IAM)** → **Roles** → **Type: CustomRole** → `Start VM Only Role` → **…** → **Delete** (works only when no assignments remain).
4. **Microsoft Entra ID** → **Users** → select `vmstarter01` → **Delete**.

---

## References

- [Azure custom roles](https://learn.microsoft.com/azure/role-based-access-control/custom-roles)
- [Create or update Azure custom roles using the Azure portal](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal)
- [Azure permissions for Compute (Microsoft.Compute)](https://learn.microsoft.com/azure/role-based-access-control/permissions/compute)
- [Assign Azure roles using the Azure portal](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal)
