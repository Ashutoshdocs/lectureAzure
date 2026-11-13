# Azure Service Health — Presenter Demo Steps

Step-by-step script for a ~45 minute live demo. Each step has **Do** (what to click or run), **Say** (talking points), and **Show** (what the audience should notice).

> Run `setup.sh` at least **10 minutes before** class. See [README.md](README.md).

---

## Before class — pre-flight checklist

- [ ] `ALERT_EMAIL="you@example.com" DEPLOY_VM=true ./setup.sh` completed without errors
- [ ] Confirmation email "You've been added to an Azure Monitor action group" received
- [ ] VM `vm-health-demo` is **Running** (`az vm show -g rg-servicehealth-demo -n vm-health-demo -d --query powerState`)
- [ ] Browser tabs open:
  1. https://azure.status.microsoft
  2. Portal → **Service Health**
  3. Portal → `vm-health-demo` → **Resource health**
  4. Portal → **Monitor → Alerts**
  5. Portal → **Resource Graph Explorer**
  6. Your email inbox
- [ ] Cloud Shell (Bash) open with this folder uploaded
- [ ] Zoom the browser to ~125% so the room can read it

---

## Step 1 — The three layers (5 min)

**Do**
1. Open **https://azure.status.microsoft**.
2. Switch to the portal and type **Service Health** in the top search bar.

**Say**
- "Azure Status is the public page. It only shows broad, widespread outages — most incidents never appear here."
- "Service Health is personalised: it only shows events that affect *your* subscriptions, *your* services and *your* regions."
- "Resource Health goes one level deeper: is *this specific VM* healthy, and if not, did Azure cause it or did we?"

**Show** — Draw or display the table from README §2. Ask: *"If your web app is slow, which of these three would you check first?"* (Answer: Resource Health on the app, then Service Health for the region.)

---

## Step 2 — Tour the Service Health blade (8 min)

**Do** — In **Service Health**, click through the left menu in this order:

| Menu item | What to point out |
|---|---|
| **Service issues** | The map of affected regions; the **Subscription / Region / Service** filters at the top. Click an issue (if any) to show *Summary*, *Issue updates*, *Impacted resources* and the **Tracking ID**. |
| **Planned maintenance** | Start/end windows and the impacted resources tab. |
| **Health advisories** | Retirements and deprecations — "these have deadlines; review monthly". |
| **Security advisories** | Note this view can require extra permissions (e.g. Security Reader / Owner) because content can be sensitive. |
| **Health history** | Past events (up to ~90 days). **Download** a *Root Cause Analysis (RCA)* / Post Incident Review if one exists. |
| **Resource health** | Shortcut into per-resource health (covered in Step 3). |
| **Health alerts** | Where the alerts we build later live. |

**Say**
- "The **Tracking ID** is the key you quote to Microsoft Support and use in your own incident tickets."
- "If the portal is quiet today, that's good news — we'll use history and Resource Graph to see past events."

**Show** — Set filters to only your subscription and region to demonstrate how Service Health is personalised.

> If there are no current events: go straight to **Health history** and pick any past event.

---

## Step 3 — Resource Health on a real resource (5 min)

**Do**
1. Open `rg-servicehealth-demo` → `vm-health-demo`.
2. In the left menu, under **Help**, click **Resource health**.

**Say**
- "Green **Available** means Azure sees no platform problems with this VM."
- "Scroll down to **Health history** — every state change for this resource, with a cause."
- "The important distinction: **Platform initiated** means Azure caused it — that can count toward SLA. **User initiated** means someone in your org stopped, resized or deleted it."

**Show** — Explain the four states: Available, Degraded, Unavailable, Unknown (README §2). Mention that not every resource type supports Resource Health, but most core services do.

---

## Step 4 — Build a Service Health alert in the portal (7 min)

> Walk through creating one live, but **do not save it** — setup already deployed the same alert as code. (Or save it and delete it afterwards.)

**Do**
1. **Service Health → Health alerts → + Create service health alert.**
2. **Scope**: your subscription.
3. **Condition**:
   - **Services**: pick a few, e.g. *Virtual Machines*, *Storage*, *App Service* (or *All*).
   - **Regions**: *Central India*, *South India*, *Global*.
   - **Event types**: *Service issue*, *Planned maintenance*, *Health advisory*, *Security advisory*.
4. **Actions** → **Select action groups** → choose `ag-servicehealth-demo`.
   - Open the action group briefly to show the notification types: Email/SMS/Push/Voice and actions: Webhook, Logic App, Azure Function, Automation Runbook, ITSM, Event Hub.
5. **Details**: name it, pick the resource group `rg-servicehealth-demo`.
6. Stop at **Review + create**.

**Say**
- "Always include **Global** as a region — some services, like Entra ID or Azure Front Door, report as global."
- "This is an *activity log alert*. There's no charge for the rule, and it fires on every update of an event, not just the first."
- "In production, send to a webhook or ITSM tool, not just email."

**Show** — Open the action group → **Test action group** → *Email* → run the test, then show the test email arriving.

---

## Step 5 — Infrastructure as code (3 min)

**Do**
1. Open `main.bicep` in the Cloud Shell editor (`code main.bicep`) or on screen.
2. Go to **Monitor → Alerts → Alert rules** and show the two deployed rules:
   - `alert-servicehealth-servicehealth-demo`
   - `alert-resourcehealth-servicehealth-demo`

**Say**
- "The portal wizard just builds this JSON. The condition is `category = ServiceHealth` plus filters on `incidentType` and region."
- "`incidentType` values map to the event types: *Incident* = service issue, *Maintenance*, *Informational* / *ActionRequired* = health advisory, *Security*."
- "Defining alerts as code means every new subscription can get the same alerts automatically — or enforce it with Azure Policy."

---

## Step 6 — Live trigger: Resource Health alert (7 min) ⭐

This is the moment that sticks. Trigger it first, then fill the wait with Step 7.

**Do**
```bash
# Deallocate the VM — this is a "User initiated" Unavailable event
az vm deallocate --resource-group rg-servicehealth-demo --name vm-health-demo --no-wait
```

**Say**
- "We just shut the VM down. Resource Health should flip it to **Unavailable**, cause **User initiated**, and our alert rule should email us."
- "This usually takes **5–15 minutes**, so while we wait, let's query health data at scale."

→ Go to **Step 7**, then come back.

**When back** (after ~10 min):
1. Refresh `vm-health-demo` → **Resource health**: now **Unavailable** (or **Unknown**) with a *user initiated* note.
2. **Monitor → Alerts**: the fired alert `alert-resourcehealth-servicehealth-demo`. Click it to show the payload (common alert schema).
3. Open the email in your inbox.

**Show** — Point out `currentHealthStatus`, `previousHealthStatus` and `cause` in the alert details. "Change `cause` to only `PlatformInitiated` and you'd ignore your own shutdowns — a design decision."

```bash
# Start the VM again (optional — fires a "resolved/Available" update)
az vm start --resource-group rg-servicehealth-demo --name vm-health-demo --no-wait
```

---

## Step 7 — Query health at scale (7 min)

### 7a. Resource Graph Explorer (portal)

**Do** — Open **Resource Graph Explorer** and paste queries from `queries.kql`:

| Query | Teaching point |
|---|---|
| **Q1** All events last 30 days | Service Health is queryable data, not just a blade |
| **Q2** Count by type → click **Charts → Donut** | Instant dashboard; **Pin to dashboard** |
| **Q6** Impacted resources | Join events to *your* resources |
| **Q7 / Q9** Resource Health states | Find every unhealthy resource across all subscriptions — the stopped VM should appear |

**Say** — "Resource Graph works across every subscription you can see, in seconds. This is how you build an org-wide health dashboard."

### 7b. Azure CLI

```bash
# Same data from the CLI
az graph query -q "ServiceHealthResources | where type =~ 'Microsoft.ResourceHealth/events' | summarize count() by tostring(properties.EventType)" -o table

# Resource Health of the demo VM
az graph query -q "HealthResources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | where properties.targetResourceId contains 'vm-health-demo' | project state=tostring(properties.availabilityState), reason=tostring(properties.reasonType)" -o table
```

### 7c. REST API

```bash
SUB_ID=$(az account show --query id -o tsv)

# Service Health events for the subscription
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01" \
  --query "value[].{title:properties.title, type:properties.eventType, status:properties.status}" -o table

# Current Resource Health of the VM
VM_ID=$(az vm show -g rg-servicehealth-demo -n vm-health-demo --query id -o tsv)
az rest --method get \
  --url "https://management.azure.com$VM_ID/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2020-05-01" \
  --query "properties.{state:availabilityState, summary:summary, reason:reasonType}"
```

**Say** — "The REST API is what you'd call from a status page, a ChatOps bot, or your own monitoring tool."

→ Return to **Step 6** to check the alert.

---

## Step 8 — Wrap-up (3 min)

**Recap slide**
1. **Azure Status** = global; **Service Health** = your subscriptions; **Resource Health** = one resource.
2. Four event types: Service issue, Planned maintenance, Health advisory, Security advisory.
3. Alerts = activity log alert + action group. Free, filterable, automatable.
4. Query everything with Resource Graph or REST.

**Best practices** — see README §7.

**Quiz questions for the class**
1. A VM went Unavailable last night. How do you find out whether Azure or a colleague caused it? → *Resource Health history: Platform vs User initiated.*
2. Why include "Global" in Service Health alert regions? → *Some services report impact as global, not regional.*
3. Where do you find the document explaining what went wrong in a past incident? → *Health history → RCA / Post Incident Review.*
4. How would you list every unhealthy resource across 50 subscriptions? → *Resource Graph `HealthResources` query.*

---

## After class

```bash
./cleanup.sh
```

---

## Student lab (optional homework)

1. Create a Service Health alert for **your** subscription that only watches *Virtual Machines* in *one* region.
2. Add a **webhook** action pointing to a test endpoint (e.g. a Logic App HTTP trigger) and inspect the JSON payload.
3. Write a Resource Graph query that lists Health advisories updated in the last 7 days.
4. Find one past event in **Health history** and summarise its RCA in three sentences.
