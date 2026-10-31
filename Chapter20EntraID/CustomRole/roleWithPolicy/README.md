# Demo: Azure Custom Role — Restricted VM Operator (Portal Guide)

This demo uses the **Azure portal UI** to show a user who has these permissions:

| Action | Allowed? | Enforced by |
|---|---|---|
| Restart the VM | ✅ Yes | Custom role |
| Start the VM | ✅ Yes | Custom role |
| Stop / deallocate the VM | ❌ No | Custom role (action not granted) |
| Delete the VM or a disk | ❌ No | Custom role (action not granted) |
| Create and attach a new data disk | ✅ Yes | Custom role |
| Detach a protected data disk | ❌ No | Azure Policy (deny) |
| Resize between B-series sizes | ✅ Yes | Custom role + Azure Policy |
| Resize to D-series (or any non-B size) | ❌ No | Azure Policy (deny) |

---

## Why a custom role alone isn't enough

Azure RBAC controls **operations**, not the **contents** of a request.

- **Restart vs. stop** are separate operations (`restart/action` vs. `powerOff/action` and `deallocate/action`), so RBAC handles them.
- **Attach disk, detach disk and resize** are all the *same* operation: an update to the VM (`Microsoft.Compute/virtualMachines/write`). RBAC can't tell them apart.

**Azure Policy** inspects what's inside the request (the VM size, the list of attached disks), so two deny policies close the gap:

| File | Purpose |
|---|---|
| `custom-role.json` | Custom role definition (upload in the portal) |
| `policy-allow-only-b-series.json` | Denies any VM size not matching `Standard_B*` |
| `policy-block-disk-detach.json` | Denies removing listed data disks from the VM |

> **Note:** Azure Policy applies to **everyone** in its scope, including admins. Admins who need an exception can create a **policy exemption**.

---

## Demo values used in this guide

| Item | Value |
|---|---|
| Resource group | `rg-customrole-demo` |
| VM name | `vm-demo01` |
| VM size | `Standard_B2s` |
| Protected data disk | `vm-demo01-datadisk-protected` |
| Demo user | `vmoperator01@<yourtenant>.onmicrosoft.com` |
| Custom role | `VM Restricted Operator` |

---

## Prerequisites

- An Azure subscription where you are **Owner** (needed to create custom roles, assign roles and assign policies).
- **User Administrator** (or higher) in Microsoft Entra ID to create users.
- Two browser sessions: your admin session, and an **InPrivate/Incognito** window for the demo user.

---

## Step 1 — Create the resource group

1. Sign in to the [Azure portal](https://portal.azure.com) as admin.
2. Search **Resource groups** → **+ Create**.
3. **Subscription**: yours · **Resource group**: `rg-customrole-demo` · **Region**: your choice.
4. **Review + create** → **Create**.

---

## Step 2 — Create the VM (B-series) with a data disk

1. Search **Virtual machines** → **+ Create** → **Azure virtual machine**.
2. **Basics** tab:
   - **Resource group**: `rg-customrole-demo`
   - **Virtual machine name**: `vm-demo01`
   - **Image**: *Windows Server 2022 Datacenter: Azure Edition* (Ubuntu works too)
   - **Size**: **See all sizes** → `Standard_B2s`
   - **Administrator account**: set a username and strong password
   - **Inbound port rules**: *None* (no RDP needed for this demo)
3. **Disks** tab:
   - Under **Data disks**, click **Create and attach a new disk**
   - **Name**: `vm-demo01-datadisk-protected` · **Size**: 4 GiB or larger → **OK**
4. Leave other tabs at defaults → **Review + create** → **Create**.
5. When deployment completes, open the VM → **Settings** → **Disks** and confirm `vm-demo01-datadisk-protected` is listed under **Data disks**.

---

## Step 3 — Create the demo user

1. Search **Microsoft Entra ID** → **Manage** → **Users** → **+ New user** → **Create new user**.
2. **User principal name**: `vmoperator01` · **Display name**: `VM Operator 01`.
3. Leave **Auto-generate password** ticked and **copy the password**.
4. **Review + create** → **Create**.

---

## Step 4 — Create the custom role from JSON

1. Open `custom-role.json` and replace `<SUBSCRIPTION-ID>` with your subscription ID.
   (Find it under **Subscriptions** in the portal.)
2. In the portal, open **Resource groups** → `rg-customrole-demo` → **Access control (IAM)**.
3. Click **+ Add** → **Add custom role**.
4. **Basics** tab:
   - **Baseline permissions**: select **Start from JSON**
   - **File**: upload the edited `custom-role.json`
   - Confirm **Custom role name** shows `VM Restricted Operator`
5. Click through **Permissions**, **Assignable scopes** and **JSON** tabs to review → **Review + create** → **Create**.

### What the role grants

| Granted | Why |
|---|---|
| `virtualMachines/read`, `instanceView/read` | See the VM and its status |
| `virtualMachines/start/action`, `restart/action` | Start and restart |
| `virtualMachines/write` | Required to attach a disk and to resize |
| `vmSizes/read`, `skus/read` | Show the size list in the Resize blade |
| `disks/read`, `disks/write` | Create a new managed disk to attach |
| `networkInterfaces/join/action` | Required on any VM update because the VM references its NIC |
| `deployments/*` (limited) | Portal operations that run as deployments |

| Not granted (listed in `notActions` for clarity) | Effect |
|---|---|
| `virtualMachines/powerOff/action`, `deallocate/action` | **Stop** button fails |
| `virtualMachines/delete`, `disks/delete` | Can't delete VM or disks |
| `virtualMachines/runCommand/action` | Can't run scripts on the VM to shut it down |

> `notActions` is **not a deny**. It only subtracts from `actions` in the same role. If the user gets another role (e.g. Contributor) elsewhere that grants these, they'll have them. Keep the demo user's other assignments empty.

---

## Step 5 — Assign the custom role to the user

1. **Resource groups** → `rg-customrole-demo` → **Access control (IAM)**.
2. **+ Add** → **Add role assignment**.
3. **Role** tab: switch the filter to **Type: CustomRole** (or search) → select **VM Restricted Operator** → **Next**.
4. **Members** tab: **+ Select members** → `vmoperator01` → **Select**.
5. **Review + assign** → **Review + assign**.
6. Confirm under **Role assignments**.

---

## Step 6 — Create and assign the Azure Policies

### 6a. Policy: allow only B-series sizes

1. Search **Policy** → **Authoring** → **Definitions** → **+ Policy definition**.
2. **Definition location**: click **…** → choose your subscription.
3. **Name**: `Demo - Allow only B-series VM sizes`.
4. **Category**: **Use existing** → *Compute*.
5. **Policy rule**: delete the sample and paste the contents of the `policyRule`, `parameters` and `mode` from `policy-allow-only-b-series.json`. The editor expects this shape:

   ```json
   {
     "mode": "All",
     "parameters": {},
     "policyRule": { ...copy from the file... }
   }
   ```

6. **Save**.
7. On the new definition, click **Assign policy**:
   - **Scope**: subscription → resource group `rg-customrole-demo` → **Select**
   - **Parameters** tab: none
   - **Non-compliance message** (optional): `Only B-series VM sizes are allowed.`
   - **Review + create** → **Create**

### 6b. Policy: block detaching the protected disk

1. **Policy** → **Definitions** → **+ Policy definition**.
2. **Definition location**: your subscription · **Name**: `Demo - Block detaching protected data disks` · **Category**: *Compute*.
3. **Policy rule**: paste `mode`, `parameters` and `policyRule` from `policy-block-disk-detach.json`.
4. **Save** → **Assign policy**:
   - **Scope**: `rg-customrole-demo`
   - **Parameters** tab (untick *Only show parameters that need input*):
     - **VM name**: `vm-demo01`
     - **Protected data disk names**: `["vm-demo01-datadisk-protected"]`
   - **Non-compliance message**: `This data disk is protected and cannot be detached.`
   - **Review + create** → **Create**

> Assign this policy **after** the protected disk is attached (Step 2), or updates to the VM will be denied.

### 6c. Wait for propagation

Role assignments usually apply within a few minutes. **Policy assignments can take up to about 30 minutes** to start enforcing. Take a break before testing.

---

## Step 7 — Sign in as the new user

1. Open an **InPrivate / Incognito** browser window.
2. Go to <https://portal.azure.com>.
3. Sign in as `vmoperator01@<yourtenant>.onmicrosoft.com` with the temporary password.
4. Set a new password when prompted.
5. Search **Virtual machines** → open `vm-demo01`.

> If the VM doesn't appear, check the portal's **directory + subscription filter** (gear icon → *Directories + subscriptions*) and make sure the subscription is selected.

---

## Step 8 — Prove the role works

Do each test as `vmoperator01`.

### Test 1 — Restart ✅

1. VM **Overview** → **Restart** → **Yes**.
2. **Expected**: notification *"Successfully restarted virtual machine"*.

### Test 2 — Stop ❌

1. VM **Overview** → **Stop** → **Yes**.
2. **Expected**: failure notification similar to:

   ```
   The client 'vmoperator01@...' does not have authorization to perform action
   'Microsoft.Compute/virtualMachines/deallocate/action' ...
   ```

### Test 3 — Add a data disk ✅

1. VM → **Settings** → **Disks** → **+ Create and attach a new disk**.
2. **Disk name**: `vm-demo01-datadisk-02` · **Size**: 4 GiB.
3. **Apply** (or **Save**).
4. **Expected**: *"Successfully updated virtual machine"* and the new disk appears in the list.

### Test 4 — Detach the protected disk ❌

1. VM → **Disks** → on the row for `vm-demo01-datadisk-protected`, click the **Detach** (X) icon.
2. **Apply** / **Save**.
3. **Expected**: failure with `RequestDisallowedByPolicy`, naming the policy *Demo - Block detaching protected data disks*.

### Test 5 — Resize within B-series ✅

1. VM → **Availability + scale** → **Size** (older layout: **Settings** → **Size**).
2. Select a B-series size such as `Standard_B2ms` → **Resize**.
3. **Expected**: *"Successfully resized virtual machine"* (the VM reboots).

> If Azure says the new size needs the VM to be **deallocated** first (size not available on the current hardware cluster), the user can't do it because they can't deallocate. Pick another B-series size, or have an admin do it.

### Test 6 — Resize to D-series ❌

1. VM → **Size** → select `Standard_D2s_v5` (or any D-series) → **Resize**.
2. **Expected**: failure with `RequestDisallowedByPolicy`, naming *Demo - Allow only B-series VM sizes*.

### Test 7 — Delete the VM ❌ (bonus)

1. VM **Overview** → **Delete**.
2. **Expected**: authorization failure for `Microsoft.Compute/virtualMachines/delete`.

### Collect the evidence

1. As admin, open the VM → **Activity log**.
2. Filter **Event initiated by** = `vmoperator01`.
3. You'll see the successful restart, disk attach and B-series resize, and failed operations showing **Status: Failed** with the authorization or policy error. Click any event → **JSON** to capture the exact message.

| Test | Expected result | Your result |
|---|---|---|
| 1. Restart | Succeeds | |
| 2. Stop | Fails — AuthorizationFailed | |
| 3. Add disk | Succeeds | |
| 4. Detach protected disk | Fails — RequestDisallowedByPolicy | |
| 5. Resize to B-series | Succeeds | |
| 6. Resize to D-series | Fails — RequestDisallowedByPolicy | |
| 7. Delete VM | Fails — AuthorizationFailed | |

---

## Known limitations

- **Only listed disks are protected.** Azure Policy only sees the new request, not the VM's previous state, so it can't detect "a disk was removed" in general. Disks that the user attaches later (like `vm-demo01-datadisk-02`) can be detached until an admin adds them to the policy's `protectedDiskNames` list (**Policy** → **Assignments** → edit → **Parameters**).
- **Shutting down from inside the OS.** If the user can sign in to the VM itself (RDP/SSH) with sufficient rights, they can shut it down from the guest OS. This demo grants no VM login role and no Run Command; keep it that way if stopping must be fully prevented.
- **Policy affects everyone.** The B-series and detach rules also block admins in this resource group. Use a **policy exemption** for planned changes.
- **Other roles add up.** RBAC is additive. Any other role the user holds at the subscription or management group level can grant the blocked actions.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| User sees *"You don't have access"* on the VM | Wait a few minutes after role assignment; check scope is the resource group. |
| Disk attach fails with `AuthorizationFailed` on `networkInterfaces/join/action` | Make sure the role JSON includes that action (re-upload the role). |
| D-series resize **succeeds** | Policy hasn't propagated yet (wait up to 30 min) or was assigned to a different scope. Check **Policy** → **Assignments**. |
| Detach **succeeds** | Disk name or VM name in the policy parameters doesn't match exactly (case and spelling). |
| Resize blade shows no sizes | Role is missing `vmSizes/read` or `skus/read`. |
| Custom role upload fails | `<SUBSCRIPTION-ID>` placeholder not replaced, or the JSON was edited into an invalid shape. |

---

## Clean up

1. **Policy** → **Assignments** → delete both demo assignments.
2. **Policy** → **Definitions** → delete both demo definitions.
3. **Resource groups** → `rg-customrole-demo` → **Access control (IAM)** → **Role assignments** → remove `vmoperator01`.
4. **Resource groups** → `rg-customrole-demo` → **Delete resource group**.
5. **Subscriptions** → your subscription → **Access control (IAM)** → **Roles** → find **VM Restricted Operator** → **…** → **Delete** (only possible once no assignments remain).
6. **Microsoft Entra ID** → **Users** → delete `vmoperator01`.

---

## References

- [Azure custom roles](https://learn.microsoft.com/azure/role-based-access-control/custom-roles)
- [Create or update Azure custom roles using the Azure portal](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal)
- [Azure resource provider operations — Microsoft.Compute](https://learn.microsoft.com/azure/role-based-access-control/permissions/compute)
- [Azure Policy definition structure](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-basics)
- [Azure Policy exemptions](https://learn.microsoft.com/azure/governance/policy/concepts/exemption-structure)
