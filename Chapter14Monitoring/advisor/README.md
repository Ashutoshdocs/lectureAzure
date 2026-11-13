# Azure Advisor – End-to-End Demo (Portal / UI Based)

A hands-on walkthrough of **Azure Advisor** using the Azure portal. You'll deploy a few deliberately "imperfect" resources, let Advisor analyze them, and then explore, act on, configure, alert on, and report on the recommendations, all from the UI.

---

## Table of Contents

1. [What is Azure Advisor?](#1-what-is-azure-advisor)
2. [Demo Architecture](#2-demo-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Step 1 – Deploy Demo Resources](#step-1--deploy-demo-resources)
5. [Step 2 – Open Azure Advisor](#step-2--open-azure-advisor)
6. [Step 3 – Explore the Advisor Score](#step-3--explore-the-advisor-score)
7. [Step 4 – Review Recommendations by Category](#step-4--review-recommendations-by-category)
8. [Step 5 – Drill Into a Recommendation](#step-5--drill-into-a-recommendation)
9. [Step 6 – Remediate (Quick Fix & Manual Fix)](#step-6--remediate-quick-fix--manual-fix)
10. [Step 7 – Postpone or Dismiss a Recommendation](#step-7--postpone-or-dismiss-a-recommendation)
11. [Step 8 – Configure Advisor](#step-8--configure-advisor)
12. [Step 9 – Create Advisor Alerts](#step-9--create-advisor-alerts)
13. [Step 10 – Set Up Recommendation Digests](#step-10--set-up-recommendation-digests)
14. [Step 11 – Download Reports](#step-11--download-reports)
15. [Step 12 – Advisor Workbooks](#step-12--advisor-workbooks)
16. [Step 13 – Query Advisor with Azure Resource Graph](#step-13--query-advisor-with-azure-resource-graph)
17. [Step 14 – Clean Up](#step-14--clean-up)
18. [Troubleshooting](#troubleshooting)
19. [Demo Script Cheat Sheet](#demo-script-cheat-sheet)
20. [References](#references)

---

## 1. What is Azure Advisor?

Azure Advisor is a free, personalized cloud consultant that analyzes your resource configuration and usage telemetry and recommends ways to improve your Azure environment. Recommendations align with the **Azure Well-Architected Framework** and fall into five categories:

| Category | What it helps with | Example recommendation |
|---|---|---|
| 💰 **Cost** | Reduce overall spend | Right-size or shut down underutilized VMs, delete unattached disks, buy reservations |
| 🔒 **Security** | Detect threats and vulnerabilities (powered by Microsoft Defender for Cloud) | Enable MFA, restrict open management ports |
| 🛡️ **Reliability** | Keep business-critical apps available | Enable VM backup, use availability zones, enable soft delete on storage |
| ⚙️ **Operational Excellence** | Process & workflow efficiency, manageability | Create Azure Service Health alerts, fix deprecated configs |
| ⚡ **Performance** | Improve speed and responsiveness | Upgrade storage tier, fix SQL query performance |

**Key points**
- No extra cost; it's enabled by default for every subscription.
- Recommendations refresh roughly every 24 hours (some cost recommendations need ~7 days of usage data).
- Scope: subscription and resource group level.
- Access requires at least **Reader** role on the subscription/resource group (Contributor or Owner to act on/configure).

---

## 2. Demo Architecture

```
Subscription
└── Resource Group: rg-advisor-demo
    ├── vm-advisor-demo        (Linux VM, no backup, oversized SKU, low CPU)   → Cost / Reliability
    ├── disk-orphaned          (Unattached managed disk)                        → Cost
    ├── pip-unused             (Unassociated Standard public IP)                → Cost
    ├── stadvisordemo<rand>    (Storage account, soft delete disabled)          → Reliability / Security
    └── nsg-open-ssh           (NSG allowing SSH 22 from Any)                    → Security
```

**Flow of the demo**

```
Deploy resources ──► Advisor analyzes (≤24h) ──► Review score & recommendations
        ──► Remediate / Postpone / Dismiss ──► Configure rules ──► Alerts & Digests
        ──► Reports, Workbooks, Resource Graph ──► Clean up
```

---

## 3. Prerequisites

- An Azure subscription (a dev/test or trial subscription is ideal).
- **Owner** or **Contributor** role on the subscription (needed to create alerts and change Advisor configuration).
- A modern browser signed in to [https://portal.azure.com](https://portal.azure.com).
- *(Optional)* Azure Cloud Shell or Azure CLI for faster resource setup.
- An email address for alert and digest notifications.

> ⏱️ **Timing tip:** Deploy the resources **at least 24 hours (ideally several days) before** presenting so recommendations have time to appear. Cost right-sizing recommendations need usage history.

---

## Step 1 – Deploy Demo Resources

### Option A – Portal (UI)

1. **Create resource group**
   - Portal → **Resource groups** → **+ Create**
   - Name: `rg-advisor-demo`, Region: e.g. `Central India` → **Review + create** → **Create**

2. **Create an oversized VM without backup**
   - **Virtual machines** → **+ Create** → **Azure virtual machine**
   - Resource group: `rg-advisor-demo`, Name: `vm-advisor-demo`
   - Image: Ubuntu Server LTS, Size: `Standard_D4s_v5` (intentionally larger than needed)
   - Inbound ports: allow **SSH (22)**
   - **Management** tab → leave **Enable backup** unchecked
   - **Review + create** → **Create**

3. **Create an orphaned disk**
   - **Disks** → **+ Create** → Name: `disk-orphaned`, Size: 128 GiB, Premium SSD → **Create**
   - Do **not** attach it to any VM.

4. **Create an unused public IP**
   - **Public IP addresses** → **+ Create** → Name: `pip-unused`, SKU: Standard → **Create**
   - Do **not** associate it.

5. **Create a storage account with soft delete disabled**
   - **Storage accounts** → **+ Create** → Name: `stadvisordemo<unique>`
   - **Data protection** tab → uncheck *soft delete for blobs* and *soft delete for containers*
   - **Review + create** → **Create**

6. **Open NSG rule**
   - The VM's NSG already allows SSH from **Any**, which surfaces a security recommendation.

### Option B – Azure CLI (Cloud Shell)

```bash
RG=rg-advisor-demo
LOC=centralindia
SA=stadvisordemo$RANDOM

az group create -n $RG -l $LOC

# Oversized VM, SSH open to the internet, no backup
az vm create -g $RG -n vm-advisor-demo \
  --image Ubuntu2204 --size Standard_D4s_v5 \
  --admin-username azureuser --generate-ssh-keys \
  --public-ip-sku Standard

# Orphaned managed disk
az disk create -g $RG -n disk-orphaned --size-gb 128 --sku Premium_LRS

# Unassociated public IP
az network public-ip create -g $RG -n pip-unused --sku Standard

# Storage account with soft delete disabled
az storage account create -g $RG -n $SA --sku Standard_LRS
az storage account blob-service-properties update -g $RG --account-name $SA \
  --enable-delete-retention false --enable-container-delete-retention false
```

✅ **Checkpoint:** `rg-advisor-demo` contains a VM, a disk, a public IP, a storage account, and supporting network resources.

---

## Step 2 – Open Azure Advisor

1. In the portal search bar, type **Advisor** and select **Advisor**.
2. You land on the **Overview** page showing:
   - **Advisor score** (overall and by category)
   - Recommendation tiles for Cost, Security, Reliability, Operational Excellence, Performance
   - Potential yearly savings (Cost)
3. Use the **Subscription** filter at the top to select your demo subscription.
4. Optionally filter by **Resource group** → `rg-advisor-demo`.

> 💡 You can also reach Advisor recommendations from an individual resource: open the VM → **Advisor recommendations** in the left menu.

---

## Step 3 – Explore the Advisor Score

1. Left menu → **Advisor score**.
2. Observe:
   - **Overall score** (0–100%): how closely your workloads follow best practices.
   - **Category scores**: the gap in each pillar.
   - **Score history** chart (trend over the last 30/60/90 days).
   - **Score impact**: which recommendations would raise the score the most.
3. Talking point: the score is weighted. Fixing recommendations on high-cost or high-impact resources moves the score more.

---

## Step 4 – Review Recommendations by Category

1. Left menu → **Recommendations** → choose a category (e.g. **Cost**).
2. Expected demo findings (exact wording may vary):

| Category | Expected recommendation | Resource |
|---|---|---|
| Cost | Right-size or shut down underutilized virtual machines | `vm-advisor-demo` |
| Cost | Delete unattached managed disks / review unattached disks | `disk-orphaned` |
| Cost | Delete unassociated public IP addresses | `pip-unused` |
| Reliability | Enable Backup to protect your VMs | `vm-advisor-demo` |
| Reliability | Enable soft delete for blobs | storage account |
| Security | Management ports should be closed / restricted | `vm-advisor-demo` / NSG |
| Operational Excellence | Create Azure Service Health alerts | subscription |

3. Use the toolbar features:
   - **Filter** by subscription, resource group, impact (High / Medium / Low), status (Active / Postponed / Dismissed).
   - **Group by** to view by resource type.
   - **Search** to find a specific recommendation.

---

## Step 5 – Drill Into a Recommendation

1. Click **Enable Backup to protect your VMs** (Reliability).
2. The details page shows:
   - **Description** and **business impact**
   - **Affected resources** list
   - **Recommended actions** and a **Learn more** link
3. Click the **Cost** recommendation **Right-size or shut down underutilized VMs**:
   - Shows **current SKU**, **recommended SKU**, average CPU/network usage, and **estimated monthly/annual savings**.

---

## Step 6 – Remediate (Quick Fix & Manual Fix)

### A. Quick Fix (bulk remediation from Advisor)
Some recommendations support **Quick Fix**, letting you remediate one or many resources directly.

1. Open a recommendation that shows a **Quick Fix** button (e.g. storage soft delete, depending on availability).
2. Select the affected resource(s) → **Quick Fix** → review settings → **Apply**.
3. Watch the **Notifications** bell for progress.

### B. Manual Fix (navigate to the resource)

**Enable VM backup**
1. From the recommendation, click **Enable backup** (or open the VM → **Backup**).
2. Create/choose a **Recovery Services vault** and a backup policy → **Enable backup**.

**Delete orphaned resources**
1. Click `disk-orphaned` → **Delete** → confirm.
2. Click `pip-unused` → **Delete** → confirm.

**Restrict SSH**
1. Open the VM's **Network settings** → edit the SSH inbound rule.
2. Change **Source** from *Any* to *My IP address* (or enable **Just-in-time VM access** via Defender for Cloud).

> ⏳ Remediated recommendations disappear after Advisor's next refresh (up to 24 hours). You can click **Refresh** on the recommendations page to request a re-evaluation.

---

## Step 7 – Postpone or Dismiss a Recommendation

Not every recommendation fits every workload. Show governance options:

1. Open the **Right-size VM** recommendation.
2. Select the VM → **Postpone** → choose 1 day / 1 week / 1 month / 3 months → **Postpone**.
3. For another recommendation, select **Dismiss** if it is not applicable.
4. Change the status filter to **Postponed** or **Dismissed** to view them.
5. To restore: select the item → **Activate**.

---

## Step 8 – Configure Advisor

Left menu → **Configuration**.

### A. Resources tab
- Include/exclude **subscriptions** or **resource groups** from Advisor evaluation (e.g. exclude a sandbox RG).

### B. VM/VMSS right sizing tab
- Set the **CPU utilization threshold** for low-usage detection: **5%, 10%, 15%, 20%, or 100%**.
- Set the **lookback period**: **7, 14, 30, 60, or 90 days**.
- Demo: change the threshold to **20%** so the demo VM is more likely to be flagged → **Apply**.

> 📝 Configuration changes take effect at the next Advisor refresh.

---

## Step 9 – Create Advisor Alerts

Advisor alerts notify you when new recommendations appear.

1. Left menu → **Alerts (Preview)** (or **Monitoring → Alerts** in Advisor) → **+ New Advisor Alert**.
2. **Scope:** select subscription (optionally resource group `rg-advisor-demo`).
3. **Condition:** configure by
   - **Category** (e.g. Cost, Reliability) and **Impact level** (High/Medium/Low), **or**
   - **Recommendation type** (a specific recommendation).
4. **Action group:** **+ Create action group**
   - Name: `ag-advisor-demo`
   - Notification type: **Email/SMS/Push/Voice** → enter your email
   - (Optional) Action: Logic App, Azure Function, Webhook, or ITSM
5. **Alert rule details:** Name `alert-advisor-cost-high`, enable on creation → **Create alert rule**.
6. Verify under **Azure Monitor → Alerts → Alert rules**.

---

## Step 10 – Set Up Recommendation Digests

Digests send a periodic email summary of active recommendations.

1. Advisor left menu → **Recommendation digests** → **+ New recommendation digest**.
2. **Name:** `digest-weekly-all`
3. **Frequency:** Weekly (or Bi-weekly / Monthly)
4. **Categories:** All (or pick specific ones)
5. **Action group:** select `ag-advisor-demo`
6. **Create**.

---

## Step 11 – Download Reports

1. From **Overview** or any recommendation list, click **Download as CSV** or **Download as PDF**.
2. Open the file to show resource names, categories, impact, and potential savings.
3. Talking point: share these with FinOps, security, or leadership teams for review.

---

## Step 12 – Advisor Workbooks

1. Advisor left menu → **Workbooks**.
2. Open templates such as **Cost Optimization**, **Reliability**, or **Service Retirement** workbooks.
3. Show filters by subscription/resource group and the visuals of savings opportunities and risks.
4. Click **Edit** → **Save as** to create a customized copy for your team.

---

## Step 13 – Query Advisor with Azure Resource Graph

1. Portal search → **Resource Graph Explorer**.
2. Run:

```kusto
advisorresources
| where type == "microsoft.advisor/recommendations"
| extend category = tostring(properties.category),
         impact   = tostring(properties.impact),
         problem  = tostring(properties.shortDescription.problem),
         resource = tostring(properties.resourceMetadata.resourceId)
| project category, impact, problem, resource, resourceGroup, subscriptionId
| order by category asc, impact asc
```

3. Summarize potential cost savings:

```kusto
advisorresources
| where type == "microsoft.advisor/recommendations"
| where properties.category == "Cost"
| extend savings  = todouble(properties.extendedProperties.annualSavingsAmount),
         currency = tostring(properties.extendedProperties.savingsCurrency)
| summarize TotalAnnualSavings = sum(savings) by currency
```

4. Click **Pin to dashboard** to add the results to an Azure dashboard.

*(Optional CLI equivalent)*

```bash
az advisor recommendation list --category Cost -o table
az advisor recommendation list --resource-group rg-advisor-demo -o table
```

---

## Step 14 – Clean Up

Delete everything created for the demo to avoid charges.

**Portal**
1. **Resource groups** → `rg-advisor-demo` → **Delete resource group** → type the name → **Delete**.
2. If you created a Recovery Services vault elsewhere, stop backup, delete backup data, then delete the vault.
3. **Monitor → Alerts → Alert rules** → delete `alert-advisor-cost-high`.
4. **Advisor → Recommendation digests** → delete `digest-weekly-all`.
5. **Monitor → Action groups** → delete `ag-advisor-demo`.

**CLI**
```bash
az group delete -n rg-advisor-demo --yes --no-wait
```

---

## Troubleshooting

| Issue | Cause / Fix |
|---|---|
| No recommendations appear | Wait up to 24 hours after deployment; click **Refresh**. Confirm the correct subscription filter. |
| No VM right-sizing recommendation | Needs usage history (at least ~7 days). Lower the lookback period or raise the CPU threshold in **Configuration**. |
| Security recommendations missing | Security recommendations come from Microsoft Defender for Cloud; ensure it's enabled on the subscription. |
| Can't create alerts or change configuration | Requires Contributor/Owner on the subscription. |
| Recommendation still shows after fixing | Advisor re-evaluates on its next cycle; refresh or wait up to 24 hours. |
| Labels in the portal differ from this guide | The Azure portal UI is updated frequently; menu names may vary slightly. |

---

## Demo Script Cheat Sheet

| Time | Segment | What to show |
|---|---|---|
| 0–3 min | Intro | What Advisor is, five pillars, free service |
| 3–6 min | Overview & Score | Advisor score, category scores, history |
| 6–12 min | Recommendations | Cost, Reliability, Security findings on demo RG |
| 12–17 min | Remediate | Enable backup, delete orphaned disk/IP, restrict SSH |
| 17–19 min | Governance | Postpone / Dismiss / Reactivate |
| 19–22 min | Configuration | Right-sizing threshold & lookback, exclude RG |
| 22–26 min | Alerts & Digests | Action group, alert rule, weekly digest |
| 26–29 min | Reporting | CSV/PDF export, Workbooks, Resource Graph query |
| 29–30 min | Wrap-up | Clean up, Q&A |

---

## References

- Azure Advisor documentation: https://learn.microsoft.com/azure/advisor/
- Advisor score: https://learn.microsoft.com/azure/advisor/azure-advisor-score
- Configure Advisor alerts: https://learn.microsoft.com/azure/advisor/advisor-alerts-portal
- Recommendation digests: https://learn.microsoft.com/azure/advisor/advisor-recommendations-digest
- Query Advisor with Resource Graph: https://learn.microsoft.com/azure/advisor/resource-graph-samples
- Azure Well-Architected Framework: https://learn.microsoft.com/azure/well-architected/

---

*Author: Your Name • Last updated: October 2026*
