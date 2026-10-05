# Azure Service Health — Teaching Demo

A hands-on, ~45-minute demo that teaches how to **see, query, and get alerted on** Azure platform health, from the global status page down to a single resource.

---

## 1. What students will learn

By the end of the demo, students can:

1. Explain the three layers of Azure health information and when to use each.
2. Navigate Service Health in the portal: Service issues, Planned maintenance, Health advisories, Security advisories, and Health history.
3. Use **Resource Health** to tell whether a problem is caused by Azure or by the user.
4. Create **Service Health alerts** and **Resource Health alerts** with an **action group**.
5. Query health events at scale with **Azure Resource Graph (KQL)** and the **REST API**.
6. Trigger a real alert live and read the notification.

---

## 2. Core concepts (whiteboard section)

| Layer | Scope | Answers the question | Where |
|---|---|---|---|
| **Azure Status** | Global, all customers | "Is there a big, widespread Azure outage?" | https://azure.status.microsoft |
| **Service Health** | *Your* subscriptions, services and regions | "Is an Azure incident or maintenance affecting **my** services?" | Portal → Service Health |
| **Resource Health** | A single resource (VM, storage, SQL DB…) | "Is **this** resource healthy right now, and why not?" | Portal → resource → Resource health |

### Service Health event types

| Event type | Meaning | Typical action |
|---|---|---|
| **Service issue** | Active incident affecting your services | Check impact, follow updates, open support case if needed |
| **Planned maintenance** | Upcoming Azure maintenance | Schedule around it, check if you can self-maintain |
| **Health advisory** | Changes needing attention (feature retirements, quota, deprecations) | Plan migration/changes before deadline |
| **Security advisory** | Security-related notifications | Review and remediate |

### Resource Health states

| State | Meaning |
|---|---|
| **Available** | No known platform problems |
| **Degraded** | Resource is working but with reduced performance |
| **Unavailable** | Resource is down — cause is shown as *Platform initiated* (Azure) or *User initiated* (you, e.g. a stopped VM) |
| **Unknown** | No health signal received recently (common for stopped resources) |

### How alerting fits together

```
Service Health / Resource Health event
            │
            ▼
   Activity Log (category = ServiceHealth / ResourceHealth)
            │
            ▼
   Activity Log Alert rule  ──filters──▶ services, regions, event types, health status
            │
            ▼
      Action Group  ──▶ Email / SMS / Push / Webhook / Logic App / Function / ITSM
```

Key teaching point: **Service Health alerts are activity log alerts** — they are free, scoped to a subscription, and fire for every matching event update.

---

## 3. What's in this kit

| File | Purpose |
|---|---|
| `README.md` | This overview and teaching guide |
| `DEMO-STEPS.md` | Presenter script, step by step, with talking points |
| `setup.sh` | Deploys the demo resources (resource group, action group, alerts, optional VM) |
| `cleanup.sh` | Deletes everything the setup created |
| `main.bicep` | Infrastructure as code for the action group and both alert rules |
| `queries.kql` | Azure Resource Graph queries for health events and resource health |

### What `setup.sh` deploys

- Resource group `rg-servicehealth-demo`
- Action group `ag-servicehealth-demo` (email notification, common alert schema)
- **Service Health alert** — subscription-wide, filtered to incidents, maintenance, advisories and security events in your chosen regions
- **Resource Health alert** — fires when a resource in the demo resource group becomes Degraded or Unavailable
- *(Optional)* a small Linux VM (`Standard_B1s`) so you can stop it live and trigger the Resource Health alert

---

## 4. Prerequisites

- An Azure subscription where you have **Contributor** (or Owner) rights
- **Azure CLI** 2.50+ (`az version`) — or use **Azure Cloud Shell (Bash)**, which has everything pre-installed
- Bicep (bundled with recent Azure CLI: `az bicep install`)
- An email address you can open during the demo
- About 10 minutes of setup time **before** class (alerts can take a few minutes to become active)

Cost: the alerts and action group are free (email notifications are included). The optional B1s VM costs a few cents per hour — run `cleanup.sh` afterwards.

---

## 5. Quick start

```bash
# 1. Sign in and pick the subscription
az login
az account set --subscription "<your-subscription-id-or-name>"

# 2. Run setup (set your email; DEPLOY_VM=true to include the demo VM)
chmod +x setup.sh cleanup.sh
ALERT_EMAIL="you@example.com" DEPLOY_VM=true ./setup.sh

# 3. Teach using DEMO-STEPS.md

# 4. Clean up after class
./cleanup.sh
```

Optional settings for `setup.sh` (environment variables):

| Variable | Default | Description |
|---|---|---|
| `ALERT_EMAIL` | *(required)* | Address that receives alert emails |
| `LOCATION` | `centralindia` | Region for the resource group and VM |
| `REGIONS` | `Central India,South India,Global` | Comma-separated region display names the Service Health alert watches |
| `RG_NAME` | `rg-servicehealth-demo` | Resource group name |
| `DEPLOY_VM` | `false` | `true` to deploy the demo VM |

---

## 6. Demo agenda (≈45 min)

| # | Section | Time |
|---|---|---|
| 1 | The three layers: Azure Status vs Service Health vs Resource Health | 5 min |
| 2 | Tour of the Service Health blade | 8 min |
| 3 | Resource Health on a real resource | 5 min |
| 4 | Build a Service Health alert in the portal (walk through) | 7 min |
| 5 | Show the IaC version (Bicep) deployed by setup | 3 min |
| 6 | **Live trigger**: stop the VM → Resource Health alert email | 7 min |
| 7 | Query health at scale with Resource Graph + REST | 7 min |
| 8 | Wrap-up, best practices, Q&A | 3 min |

Full presenter script: **[DEMO-STEPS.md](DEMO-STEPS.md)**

---

## 7. Best practices to close with

- **Create Service Health alerts in every production subscription** — nobody watches the portal 24/7.
- **Filter alerts by region and service** to cut noise, but keep a broad "all incidents" alert for on-call.
- **Route to more than email**: webhooks to Teams/Slack, ITSM tickets, or Logic Apps for automation.
- **Use Resource Health alerts** on critical resources and include both *Platform initiated* and *User initiated* causes so you also catch accidental shutdowns.
- **Review Health advisories monthly** — retirements and deprecations have hard deadlines.
- **Export or query history** (Resource Graph, REST) for post-incident reviews and SLA claims.
- **Manage alerts as code** (Bicep / Terraform / Azure Policy) so new subscriptions get them automatically.

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| No alert email after stopping the VM | Resource Health can take 5–15 minutes to emit the event. Check spam, and check *Monitor → Alerts* for fired alerts. |
| No events in Service Health | Normal on a quiet day — use *Health history* and the Resource Graph queries to show past events. |
| `az graph` not found | `az extension add --name resource-graph` |
| Bicep deployment fails on regions | Region names must be display names, e.g. `Central India`, `East US`, `Global`. |
| Permission errors | You need Contributor on the subscription to create subscription-scoped alerts. |

---

## 9. Further reading

- Azure Service Health overview — https://learn.microsoft.com/azure/service-health/overview
- Resource Health overview — https://learn.microsoft.com/azure/service-health/resource-health-overview
- Create Service Health alerts — https://learn.microsoft.com/azure/service-health/alerts-activity-log-service-notifications-portal
- Resource Graph sample queries for Service Health — https://learn.microsoft.com/azure/service-health/resource-graph-samples
