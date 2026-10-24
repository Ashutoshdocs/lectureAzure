# Azure Event Grid Hands-On Lab (Portal / UI Based)

**Event Grid + Web App + Virtual Machine + Logic Apps: 2 Tasks, 2 Actions**

This lab teaches Azure Event Grid by building two event-driven scenarios in the **Azure Portal**. The Web App runs **your own code** (a small, dependency-free Node.js app in the `webapp/` folder), which you deploy from GitHub through the Portal. Everything else is point-and-click.

| | Task 1: Storage Blob Events | Task 2: Virtual Machine Events |
|---|---|---|
| **Event source** | Storage Account (blob uploaded) | Resource Group (VM stopped / deallocated) |
| **Event Grid topic type** | System topic: `Microsoft.Storage.StorageAccounts` | System topic: `Microsoft.Resources.ResourceGroups` |
| **Subscriber 1** | Web App (your own Node.js viewer), shows events live | Web App (your own Node.js viewer), shows events live |
| **Subscriber 2** | Logic App **Action 1: send an email notification** | Logic App **Action 2: automatically restart the VM** (self-healing) |

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Learning Objectives](#2-learning-objectives)
3. [Prerequisites](#3-prerequisites)
4. [Naming Conventions](#4-naming-conventions)
5. [Part 0: Build the Base Environment](#5-part-0--build-the-base-environment)
6. [Task 1: Blob Upload → Web App + Email (Action 1)](#6-task-1--blob-upload--web-app--email-action-1)
7. [Task 2: VM Deallocated → Web App + Auto-Restart (Action 2)](#7-task-2--vm-deallocated--web-app--auto-restart-action-2)
8. [Verify and Explore](#8-verify-and-explore)
9. [Troubleshooting](#9-troubleshooting)
10. [Clean Up](#10-clean-up)
11. [Key Concepts Recap](#11-key-concepts-recap)

---

## 1. Architecture

```
                         ┌──────────────────────────────┐
  TASK 1                 │        AZURE EVENT GRID       │
                         │                              │
 ┌──────────────┐ blob   │  System Topic: st-topic      │   sub-viewer-blob   ┌────────────────────┐
 │   Storage    │ created│  ┌────────────────────────┐  │ ──────────────────► │  Web App           │
 │   Account    ├───────►│  │ BlobCreated events     │  │                     │  (your Node.js     │
 └──────────────┘        │  └────────────────────────┘  │   sub-logic-email   │   viewer)          │
                         │                              │ ───────┐            │  /api/updates      │
                         │                              │        ▼            └────────────────────┘
                         │                              │  ┌────────────────────┐        ▲
                         │                              │  │ Logic App 1        │        │
                         │                              │  │ ACTION 1:          │        │
                         │                              │  │ Send email         │        │
                         │                              │  └────────────────────┘        │
  TASK 2                 │                              │                                │
 ┌──────────────┐ VM     │  System Topic: rg-topic      │   sub-viewer-vm                │
 │ Virtual      │ deallo-│  ┌────────────────────────┐  │ ───────────────────────────────┘
 │ Machine (in  ├───────►│  │ ResourceActionSuccess  │  │
 │ Resource Grp)│ cated  │  └────────────────────────┘  │   sub-logic-restart ┌────────────────────┐
 └──────▲───────┘        │                              │ ──────────────────► │ Logic App 2        │
        │                └──────────────────────────────┘                     │ ACTION 2:          │
        │                                                                     │ Start the VM       │
        └─────────────────────────── restarts VM (Managed Identity) ──────────┤                    │
                                                                              └────────────────────┘
```

**Flow summary**

- **Publisher (source):** emits an event (Storage account or Resource Group).
- **Topic:** the endpoint where the source sends events (here, *system topics* managed by Azure).
- **Event subscription:** a route plus a filter that decides *which* events go *where*.
- **Handler (subscriber):** reacts to the event (Web App webhook, Logic App).

---

## 2. Learning Objectives

By the end of this lab you will be able to:

- Explain **publishers, topics, event subscriptions, and handlers**.
- Create **system topics** for a Storage Account and a Resource Group.
- Write and deploy **your own Web App** as a webhook endpoint and implement **endpoint validation** yourself.
- Fan out one event to **multiple subscribers**.
- Use **event type filters, subject filters, and advanced filters**.
- Build two Logic Apps that perform **different actions** (notify vs. remediate).
- Use a **Managed Identity** with RBAC so a Logic App can act on a VM.
- Troubleshoot delivery using **metrics, retry policy, and dead-lettering**.

---

## 3. Prerequisites

| Requirement | Notes |
|---|---|
| Azure subscription | Owner or Contributor + User Access Administrator (needed for role assignment in Task 2) |
| GitHub account | To host the `webapp/` code and deploy it via the Deployment Center |
| Email account | Outlook.com / Office 365 (or Gmail) for the email connector in Task 1 |
| Browser | Use any modern browser and sign in at https://portal.azure.com |
| Resource provider | `Microsoft.EventGrid` must be registered (see Step 0.1) |
| Estimated time | 75–90 minutes |
| Estimated cost | A few dollars if you clean up the same day (the VM is the main cost) |

---

## 4. Naming Conventions

Replace `<initials>` with your own short initials to keep names globally unique.

| Resource | Name used in this lab |
|---|---|
| Resource group | `rg-eventgrid-lab` |
| Region | Pick one region and use it everywhere (e.g. `Central India`) |
| Storage account | `steglab<initials>` (lowercase, no dashes) |
| Blob container | `uploads` |
| Virtual machine | `vm-eglab` |
| Web App | `app-egviewer-<initials>` |
| Logic App 1 | `logic-eg-email` |
| Logic App 2 | `logic-eg-vm-restart` |
| System topic (storage) | `st-topic` |
| System topic (resource group) | `rg-topic` |

---

## 5. Part 0: Build the Base Environment

### Step 0.1: Register the Event Grid resource provider

1. In the Portal search bar, type **Subscriptions** and open your subscription.
2. In the left menu, choose **Settings → Resource providers**.
3. Search for `Microsoft.EventGrid`.
4. If the status is **NotRegistered**, select it and click **Register**. Wait until it shows **Registered**.

### Step 0.2: Create the resource group

1. Search for **Resource groups** and click **+ Create**.
2. Enter the name `rg-eventgrid-lab` and choose your region.
3. Click **Review + create**, then **Create**.

### Step 0.3: Create the storage account (Task 1 source)

1. Search for **Storage accounts** and click **+ Create**.
2. On the **Basics** tab, fill in:
   - Resource group: `rg-eventgrid-lab`
   - Name: `steglab<initials>`
   - Region: same as your resource group
   - Performance: **Standard**
   - Redundancy: **LRS**
3. Click **Review + create**, then **Create**.
4. When it's ready, open the account and go to **Data storage → Containers → + Container**.
5. Name it `uploads`, keep it Private, and click **Create**.

> ℹ️ Blob events require a **StorageV2 (general purpose v2)** or **BlobStorage** account. The default is fine.

### Step 0.4: Create the virtual machine (Task 2 source)

1. Search for **Virtual machines**, then click **+ Create → Azure virtual machine**.
2. On the **Basics** tab, fill in:
   - Resource group: `rg-eventgrid-lab`
   - VM name: `vm-eglab`
   - Region: same as before
   - Image: **Ubuntu Server 24.04 LTS** (or Windows Server)
   - Size: **Standard_B1s** (or the cheapest available)
   - Authentication: password or SSH key
   - Public inbound ports: **None** (you won't log in)
3. Click **Review + create**, then **Create**.
4. Wait for the deployment to finish, then confirm the VM status is **Running**.

### Step 0.5: Deploy the Web App (your own code)

The Web App runs **your own Node.js code** from the `webapp/` folder. It has **zero npm dependencies**, so there's nothing to install or build. The app:

- receives events from Event Grid at `POST /api/updates`
- answers Event Grid's **subscription validation handshake** (Event Grid schema *and* CloudEvents)
- keeps the last 200 events in memory
- pushes them live to a browser page using Server-Sent Events

#### Project structure

```
webapp/
├── package.json        # "start": "node server.js" (no dependencies)
├── server.js           # webhook + validation + live stream + API
└── public/
    └── index.html      # live event viewer UI (color-coded by Task 1 / Task 2)
```

| Route | Purpose |
|---|---|
| `POST /api/updates` | Event Grid webhook endpoint (validation handshake + events) |
| `OPTIONS /api/updates` | CloudEvents v1.0 validation handshake |
| `GET /api/events` | JSON list of received events |
| `DELETE /api/events` | Clear the list |
| `GET /api/stream` | Live stream (Server-Sent Events) used by the UI |
| `GET /health` | Health check |
| `GET /` | Viewer UI |

#### The key code: endpoint validation

When you create a Web Hook subscription, Event Grid first POSTs a `Microsoft.EventGrid.SubscriptionValidationEvent`. Your code must reply with the `validationCode`, or the subscription creation fails:

```js
if (evt.eventType === "Microsoft.EventGrid.SubscriptionValidationEvent") {
  const code = evt.data && evt.data.validationCode;
  return send(res, 200, { validationResponse: code });
}
```

Every other event is stored and broadcast to the browser:

```js
for (const evt of list) store(evt, "webhook");
return send(res, 200, { received: list.length });
```

> 🎓 **Teaching point:** Event Grid treats any `200`–`204` response as *delivered*. Any other status (or a timeout) triggers the **retry policy** and, eventually, **dead-lettering**.

#### 0.5.1: Push the code to GitHub

1. On GitHub, click **New repository** and name it `eventgrid-lab-viewer`. Make it Public or Private.
2. Upload the **contents** of the `webapp/` folder so that `package.json` and `server.js` sit at the **root** of the repo:
   - Click **Add file → Upload files**.
   - Drag in `package.json`, `server.js`, and the `public` folder.
   - Click **Commit changes** on the `main` branch.

> ⚠️ `package.json` must be at the repo root, not inside a `webapp/` subfolder. Otherwise App Service won't find your app.

*(Optional) Test locally first:* run `node server.js` in the `webapp` folder, then open http://localhost:8080.

#### 0.5.2: Create the Web App

1. Search for **App Services**, then click **+ Create → Web App**.
2. On the **Basics** tab, fill in:

   | Field | Value |
   |---|---|
   | Resource group | `rg-eventgrid-lab` |
   | Name | `app-egviewer-<initials>` |
   | Publish | **Code** |
   | Runtime stack | **Node 22 LTS** (or 20 LTS) |
   | Operating System | **Linux** |
   | Region | same as before |
   | Pricing plan | **Basic B1** (recommended) or **Free F1** |

3. Click **Review + create**, then **Create**, then **Go to resource**.

#### 0.5.3: Deploy your code from GitHub

1. In the Web App, go to **Deployment → Deployment Center**.
2. On the **Settings** tab, fill in:
   - Source: **GitHub** → **Authorize** and sign in
   - Organization: your GitHub account
   - Repository: `eventgrid-lab-viewer`
   - Branch: `main`
   - Authentication type: **Basic authentication** if offered, or keep the default (**User-assigned identity**)
3. Click **Save**. This creates a GitHub Actions workflow in your repo that builds and deploys the app.
4. Open the **Logs** tab and wait until the deployment shows **Success (Active)**. You can also watch it under the repo's **Actions** tab on GitHub.

> 💡 Every `git push` to `main` now redeploys automatically. Edit the code, push, and your changes go live. That's a nice way to extend the lab.

#### 0.5.4: Configure the app

1. Go to **Settings → Configuration → General settings**.
   - Set **Startup Command** to `node server.js`
   - If you chose **Basic B1**, turn **Always On** to **On**. This keeps the in-memory event list from being lost when the app idles.
   - Click **Save**.
2. *(Optional, recommended)* Protect the webhook with a shared key:
   - Go to **Settings → Environment variables → + Add**.
   - Name: `WEBHOOK_KEY`, Value: any random string, e.g. `lab-7f3k9q`
   - Click **Apply**, then **Apply** again and confirm the restart.
   - From now on, the webhook endpoint becomes `.../api/updates?key=lab-7f3k9q`. Calls without the key get `401`.

**Verify**

1. Browse to `https://app-egviewer-<initials>.azurewebsites.net/health`. You should see `{"status":"ok","events":0}`.
2. Browse to `https://app-egviewer-<initials>.azurewebsites.net`. You'll see the **Event Grid Lab Viewer** with a green **Live** indicator. **Keep this tab open** for the rest of the lab.
3. *(Optional)* Open **Monitoring → Log stream** in a second tab. Your `console.log` lines appear there as events arrive.

> 📌 The webhook endpoint you'll give Event Grid is:
> `https://app-egviewer-<initials>.azurewebsites.net/api/updates`
> (append `?key=<your WEBHOOK_KEY>` if you set one)

✅ **Checkpoint:** Your resource group now contains a storage account, a VM (plus its disk, NIC, and VNet), and a Web App.

---

## 6. Task 1: Blob Upload → Web App + Email (Action 1)

**Goal:** When a file is uploaded to the `uploads` container, Event Grid sends the event to:
- the **Web App** (so you can see the raw JSON event), and
- **Logic App 1**, which **sends an email** containing the file name, size, and URL.

### Step 1.1: Subscribe the Web App to storage events

1. Open your storage account `steglab<initials>`.
2. In the left menu, click **Events**.
3. Click **+ Event Subscription**.
4. On the **Basic** tab, fill in:

   | Field | Value |
   |---|---|
   | Name | `sub-viewer-blob` |
   | Event Schema | **Event Grid Schema** |
   | System Topic Name | `st-topic` (created automatically on first subscription) |
   | Filter to Event Types | Check **Blob Created** and **Blob Deleted** only |
   | Endpoint Type | **Web Hook** |
   | Endpoint | `https://app-egviewer-<initials>.azurewebsites.net/api/updates` (add `?key=...` if you set `WEBHOOK_KEY`) → **Confirm Selection** |

5. Click **Create**.
6. Switch to the Web App tab. You'll see a **`Microsoft.EventGrid.SubscriptionValidationEvent`**. Your code answered it with the `validationCode` (see `handleWebhook` in `server.js`). This handshake proves you own the endpoint. In **Log stream** you'll see the line `Validation handshake, replying with validationCode ...`.

> 🎓 **Teaching point: endpoint validation.** Before Event Grid delivers real events to a webhook, it sends a validation event. The endpoint must echo back the `validationCode` (or open the `validationUrl`). Your `server.js` does this in about five lines of code. Azure Functions, Logic Apps, and Azure Automation handlers are validated automatically.

### Step 1.2: Test the Web App subscription

1. In the storage account, go to **Containers → uploads → Upload**.
2. Upload any small file (e.g. `hello.txt`).
3. Check the Web App tab. A green **Task 1 · Blob** card for **`Microsoft.Storage.BlobCreated`** appears within seconds.
4. Click the card to expand the raw JSON and look at these fields:
   - `subject`: `/blobServices/default/containers/uploads/blobs/hello.txt`
   - `data.url`: the blob URL
   - `data.contentLength`: the file size in bytes

### Step 1.3: Create Logic App 1 (Action 1: send email)

1. Search for **Logic apps**, then click **+ Add**.
2. Select **Consumption** as the plan type and click **Select**.
3. Fill in:
   - Resource group: `rg-eventgrid-lab`
   - Logic App name: `logic-eg-email`
   - Region: same as before
4. Click **Review + create**, then **Create**, then **Go to resource**.

### Step 1.4: Add the Event Grid trigger

1. Open **Logic app designer**.
2. Click **Add a trigger**, search for **Event Grid**, and select **When a resource event occurs**.
3. Click **Sign in** and authenticate with your Azure account. (Or select **Connect with managed identity** if your tenant requires it.)
4. Configure the trigger:

   | Field | Value |
   |---|---|
   | Subscription | your subscription |
   | Resource Type | `Microsoft.Storage.StorageAccounts` |
   | Resource Name | `steglab<initials>` |
   | Event Type Item 1 | `Microsoft.Storage.BlobCreated` |

5. Click **Add new parameter**, select **Prefix Filter**, and enter `/blobServices/default/containers/uploads/`
6. Also add **Subscription Name** and enter `sub-logic-email`

> 🎓 **Teaching point:** Saving this trigger automatically creates an **event subscription** on the same system topic `st-topic`. One topic now has **two subscribers**. That's called *fan-out*.

### Step 1.5: Add Action 1 (send an email)

1. Under the trigger, click **+ → Add an action**.
2. Search for **Outlook.com** (or **Office 365 Outlook** / **Gmail**) and select **Send an email (V2)**.
3. Sign in to your email account.
4. Configure the email:
   - **To:** your email address
   - **Subject:** `New file uploaded:` then insert the dynamic content **Subject**
   - **Body:**

     ```
     A new blob was uploaded.

     Event type : [Event Type]
     Subject    : [Subject]
     Time       : [Event Time]
     Blob URL   : [expression → triggerBody()?['data']?['url']]
     Size bytes : [expression → triggerBody()?['data']?['contentLength']]
     ```

     To insert an expression, click in the field, select the **fx** (Expression) icon, paste the expression, and click **Add**.
5. Click **Save**.

### Step 1.6: Test Task 1

1. Upload a second file, e.g. `report.pdf`, to the `uploads` container.
2. Check all three places:
   - **Web App tab:** a new `BlobCreated` event appears.
   - **Logic App → Overview → Runs history:** a **Succeeded** run appears.
   - **Your inbox:** an email with the file details arrives.
3. Delete a blob. You'll see a `BlobDeleted` event in the Web App only, but **no email**. This happens because the Logic App filters for `BlobCreated` only.

✅ **Checkpoint:** One event goes to two subscribers, and filters control who receives what.

### Step 1.7: Inspect the system topic

1. Search for **Event Grid System Topics** and open `st-topic`.
2. Under **Event Subscriptions**, you should see `sub-viewer-blob` (Web Hook) and `sub-logic-email` (Logic App).
3. Open **Metrics** and add **Published Events**, **Delivered Events**, and **Matched Events**.

---

## 7. Task 2: VM Deallocated → Web App + Auto-Restart (Action 2)

**Goal:** When someone **stops (deallocates)** `vm-eglab`, Event Grid sends the event to:
- the **Web App** (to see the management-plane event), and
- **Logic App 2**, which **automatically starts the VM again**. This is a simple *self-healing* or policy-enforcement pattern.

> ℹ️ VMs don't have their own Event Grid topic. VM operations are captured as **Azure Resource Manager events** on the **resource group** (or subscription). The key event type is `Microsoft.Resources.ResourceActionSuccess`, and `data.operationName` tells you *which* action happened.

| Portal action on VM | `data.operationName` |
|---|---|
| Stop (deallocate) | `Microsoft.Compute/virtualMachines/deallocate/action` |
| Start | `Microsoft.Compute/virtualMachines/start/action` |
| Restart | `Microsoft.Compute/virtualMachines/restart/action` |
| Power off (from OS / API) | `Microsoft.Compute/virtualMachines/powerOff/action` |

### Step 2.1: Subscribe the Web App to resource group events

1. Open the resource group `rg-eventgrid-lab`.
2. In the left menu, click **Events**, then **+ Event Subscription**.
3. On the **Basic** tab, fill in:

   | Field | Value |
   |---|---|
   | Name | `sub-viewer-vm` |
   | Event Schema | **Event Grid Schema** |
   | System Topic Name | `rg-topic` |
   | Filter to Event Types | **Resource Action Success**, **Resource Write Success**, **Resource Delete Success** |
   | Endpoint Type | **Web Hook** |
   | Endpoint | `https://app-egviewer-<initials>.azurewebsites.net/api/updates` (add `?key=...` if you set `WEBHOOK_KEY`) |

4. Go to the **Filters** tab:
   - Check **Enable subject filtering**.
   - Set **Subject Begins With** to:
     ```
     /subscriptions/<your-subscription-id>/resourceGroups/rg-eventgrid-lab/providers/Microsoft.Compute/virtualMachines/vm-eglab
     ```
     (Copy the exact Resource ID from **VM → Overview → JSON View → Resource ID**. Note that the subject is case-sensitive unless you check *Case-sensitive subject matching* off.)
5. Click **Create**. A validation event appears in the Web App.

### Step 2.2: Create Logic App 2 with a Managed Identity

1. Go to **Logic apps → + Add → Consumption**.
2. Name it `logic-eg-vm-restart`, using the same resource group and region. Click **Create**.
3. Open the Logic App and go to **Settings → Identity → System assigned**.
4. Set Status to **On**, click **Save**, and confirm with **Yes**.

### Step 2.3: Grant the Logic App permission to start the VM

1. Open `vm-eglab` and go to **Access control (IAM) → + Add → Add role assignment**.
2. On the **Role** tab, select **Virtual Machine Contributor** and click **Next**.
3. On the **Members** tab:
   - Assign access to: **Managed identity**
   - Click **+ Select members**, choose Logic App, then select `logic-eg-vm-restart`
4. Click **Review + assign**.

> 🎓 **Teaching point: least privilege.** The Logic App can manage *only this VM*. It doesn't need any secrets or passwords.

### Step 2.4: Add the Event Grid trigger

1. Open **Logic app designer → Add a trigger → Azure Event Grid → When a resource event occurs**.
2. Sign in (or choose your managed identity connection).
3. Configure the trigger:

   | Field | Value |
   |---|---|
   | Subscription | your subscription |
   | Resource Type | `Microsoft.Resources.resourceGroups` |
   | Resource Name | `rg-eventgrid-lab` |
   | Event Type Item 1 | `Microsoft.Resources.ResourceActionSuccess` |
   | Prefix Filter | `/subscriptions/<sub-id>/resourceGroups/rg-eventgrid-lab/providers/Microsoft.Compute/virtualMachines/vm-eglab` |
   | Subscription Name | `sub-logic-restart` |

### Step 2.5: Add a condition so only "deallocate" triggers the action

This step is critical. Without it, the Logic App would also react to its *own* `start` action and could loop.

1. Click **+ → Add an action → Control → Condition**.
2. In the left value box, click **fx** and enter:
   ```
   triggerBody()?['data']?['operationName']
   ```
3. Set the operator to **is equal to**.
4. Set the right value to:
   ```
   Microsoft.Compute/virtualMachines/deallocate/action
   ```

### Step 2.6: Add Action 2 (start the VM)

1. In the **True** branch, click **+ → Add an action**.
2. Search for **Azure VM** and select **Start virtual machine**.
3. Create the connection:
   - Authentication type: **Logic Apps Managed Identity**
   - Connection name: `vm-mi-connection`
4. Configure the action:
   - Subscription: your subscription
   - Resource Group: `rg-eventgrid-lab`
   - Virtual Machine: `vm-eglab`
5. *(Optional)* After **Start virtual machine**, add **Send an email (V2)** with the subject `VM vm-eglab was stopped and has been auto-restarted`.
6. Leave the **False** branch empty.
7. Click **Save**.

> 💡 **Production tip:** Instead of hard-coding the VM name, you can parse it from the event `subject` using
> `last(split(triggerBody()?['subject'], '/'))`, which lets one Logic App protect many VMs.

### Step 2.7: Test Task 2

1. Open `vm-eglab` and click **Stop**, then confirm. Wait until the status shows **Stopped (deallocated)**.
2. Watch the Web App tab. You'll see several events:
   - `Microsoft.Resources.ResourceActionSuccess` with `operationName` = `.../deallocate/action`
   - `ResourceWriteSuccess` events (VM state/property updates)
3. Open **Logic App 2 → Runs history**. You should see:
   - A run where the condition is **True** and **Start virtual machine** ran ✅
4. Within a few minutes, the VM status returns to **Running**.
5. Back in the Web App, a new event with `operationName` = `.../start/action` appears.
6. In Logic App 2, a second run appears where the condition is **False**, so nothing happens. This proves the loop protection works.

✅ **Checkpoint:** You've built an event-driven remediation. The infrastructure fixes itself.

---

## 8. Verify and Explore

### 8.1 Compare the two actions

| | Action 1 (Task 1) | Action 2 (Task 2) |
|---|---|---|
| Logic App | `logic-eg-email` | `logic-eg-vm-restart` |
| Pattern | **Notify**: tell a human | **Remediate**: fix automatically |
| Connector | Outlook / Office 365 / Gmail | Azure VM |
| Auth | User OAuth connection | **System-assigned Managed Identity** |
| Filtering | Event type + subject prefix (in trigger) | Event type + subject prefix + **Condition on `operationName`** |

### 8.2 Compare the two tasks

| | Task 1 | Task 2 |
|---|---|---|
| Event plane | **Data plane** (blob content changed) | **Control/management plane** (ARM operation) |
| Topic type | Storage Account system topic | Resource Group system topic |
| Event types | `BlobCreated`, `BlobDeleted` | `ResourceActionSuccess`, `ResourceWriteSuccess`, ... |
| Typical use | File processing, ETL, thumbnails | Governance, auditing, auto-remediation |

### 8.3 Extra exercises (optional)

1. **Advanced filter:** Edit `sub-viewer-blob`. On the **Filters** tab, add an **advanced filter** with key `data.contentLength` and operator **Number greater than** `1024`. Upload a tiny file and a larger file and compare the results.
2. **Suffix filter:** On `sub-logic-email`, set **Subject Ends With** to `.pdf` so only PDFs trigger the email.
3. **Dead-lettering:** On `sub-viewer-blob`, go to **Additional Features**, check **Enable dead-lettering**, and choose a container named `deadletter`. Then stop the Web App and upload a file. After retries expire, the undeliverable event lands in the dead-letter container. (Shorten the time by setting the **Retry policy** to max 1 attempt and a TTL of 1 minute.)
4. **Delete detection:** Add a third subscription on `rg-topic` filtered to `ResourceDeleteSuccess` that emails you when anything in the resource group is deleted.

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Webhook validation handshake failed" when creating the Web Hook subscription | Web App not running, the URL is missing `/api/updates`, or the code didn't deploy | Browse to `/health` first to wake the app. Check the URL includes `https://` and `/api/updates` (plus `?key=...` if you set `WEBHOOK_KEY`). Check **Log stream** for the `Validation handshake` line. |
| Web App shows "Application Error" or the default welcome page | Build/startup failed, or files aren't at the repo root | Check **Deployment Center → Logs** and **Log stream**. Make sure `package.json` and `server.js` are at the root of the deployed branch. Set the startup command to `node server.js`. |
| Viewer stays on "Reconnecting…" | Live stream blocked or app restarting | Refresh the page. Events still arrive; the list reloads from `/api/events`. |
| Events vanish after a while | Events are kept in memory; the app unloads when idle or restarts | Expected in this lab. Turn on **Always On** (Basic tier and above) or re-trigger the event. |
| `401` in Event Grid delivery failures | `WEBHOOK_KEY` is set but the subscription URL has no key or the wrong key | Edit the subscription endpoint and add the correct `?key=`. |
| No events in the Web App | Event type filter doesn't match | Open the subscription and check **Filters**. Look at **Metrics → Matched Events**. |
| Logic App never runs | Trigger subscription failed to create | Open **System topic → Event Subscriptions** and confirm `sub-logic-*` exists with the status **Succeeded**. |
| Logic App 2 fails with **AuthorizationFailed** | Missing role assignment | Re-check Step 2.3. Role assignments can take 2–5 minutes to take effect. |
| VM restarts in a loop | Missing Condition in Step 2.5 | Make sure the condition checks for `deallocate/action` only. |
| Too many VM events | Subject filter is too broad | Use the full VM Resource ID as the prefix. |
| Email not received | Connector not authorized, or the message went to spam | Re-authorize the connection under **API connections** and check your junk folder. |
| `Microsoft.EventGrid` error on create | Provider not registered | Repeat Step 0.1. |

**Where to look**

- **Event Grid System Topic → Metrics:** Published / Matched / Delivered / Failed / Dead-lettered events
- **Event subscription → Metrics:** delivery success rate and latency
- **Logic App → Runs history:** step-by-step inputs and outputs for each run

---

## 10. Clean Up

To avoid charges (especially for the VM):

1. *(Important)* First **disable** Logic App 2 (**Overview → Disable**). Otherwise it may keep restarting the VM while you delete things.
2. Go to **Resource groups → `rg-eventgrid-lab` → Delete resource group**.
3. Type the resource group name to confirm, then click **Delete**.

This removes the VM, storage account, Web App, Logic Apps, system topics, and all event subscriptions.

---

## 11. Key Concepts Recap

| Concept | What it means | Where you used it |
|---|---|---|
| **Event** | A small JSON message describing *what happened* | `BlobCreated`, `ResourceActionSuccess` |
| **Publisher / Source** | The service that emits the event | Storage account, Resource group |
| **System Topic** | An Azure-managed topic for an Azure service | `st-topic`, `rg-topic` |
| **Event Subscription** | Route + filter → handler | 4 subscriptions in total |
| **Handler** | The endpoint that reacts | Web App webhook, Logic Apps |
| **Fan-out** | One event delivered to many handlers | Viewer + Logic App on each topic |
| **Filtering** | Event type, subject prefix/suffix, advanced filters | Every subscription |
| **Validation handshake** | Proves webhook ownership | Your `server.js` echoes `validationCode` |
| **Retry & dead-letter** | Guaranteed at-least-once delivery | Extra exercise 3 |
| **Push model** | Event Grid pushes to handlers (no polling) | The whole lab |

### Event Grid event structure (example)

```json
{
  "id": "1807…",
  "topic": "/subscriptions/<sub>/resourceGroups/rg-eventgrid-lab/providers/Microsoft.Storage/storageAccounts/steglab<initials>",
  "subject": "/blobServices/default/containers/uploads/blobs/hello.txt",
  "eventType": "Microsoft.Storage.BlobCreated",
  "eventTime": "2026-10-24T15:12:03.123Z",
  "data": {
    "api": "PutBlob",
    "contentType": "text/plain",
    "contentLength": 524,
    "blobType": "BlockBlob",
    "url": "https://steglab<initials>.blob.core.windows.net/uploads/hello.txt"
  },
  "dataVersion": "",
  "metadataVersion": "1"
}
```

---

🎉 **Lab complete!** You've built two event-driven workflows with Azure Event Grid: one that **notifies** and one that **remediates**, both observable live through a Web App running your own code.
