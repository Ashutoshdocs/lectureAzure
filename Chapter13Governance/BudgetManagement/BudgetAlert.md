# 📘 Azure Cost Management – Budget, Alerts & Cost Optimization

## AZ-104 Practical Lab

## 1. Objective

In this practical, we will learn how to monitor, analyze, control, and optimize Azure cloud spending using **Azure Cost Management + Billing**.

We will create Azure resources, monitor their consumption, configure budgets, receive email alerts, analyze spending, and configure automated responses.

### What we will implement

1. Understand Azure Cost Management.
2. Create a Resource Group and Azure resources for testing.
3. Explore Cost Analysis.
4. Create a subscription-level budget.
5. Create a resource-group-level budget.
6. Configure actual cost alerts.
7. Configure forecasted cost alerts.
8. Configure cost anomaly alerts.
9. Create scheduled cost reports.
10. Export cost details to an Azure Storage Account.
11. Use Azure Advisor for cost optimization.
12. Configure an Action Group for budget notifications and automated responses.
13. Understand Azure Cost Management RBAC permissions.
14. Clean up the resources.

---

# 2. Architecture

```text
                  Azure Subscription
                         |
                  Cost Management
                         |
            +------------+-------------+
            |            |             |
        Cost Analysis  Budgets     Cost Alerts
            |            |             |
       Cost Reports   Thresholds    Notifications
                         |             |
                  +------+-----+       |
                  |            |       |
                Actual     Forecast    |
                  |            |       |
                  +------+-----+       |
                         |             |
                    Action Group <-----+
                         |
               +---------+---------+
               |                   |
            Email             Logic App
                                   |
                            Automation Runbook
                                   |
                          Controlled Remediation

                 Cost Management
                         |
                    Cost Exports
                         |
                  Azure Storage
                         |
                    CSV Reports
```

---

# 3. Prerequisites

- Active Azure subscription.
- Azure Portal access.
- Permission to manage Cost Management budgets.
- Permission to create Azure resources.
- An email address for receiving alerts.
- Azure Storage Account for the export practical (optional).

**Important:** Cost Management features are available without an additional charge, but the Azure resources created for this practical may incur charges.

---

# PART 1 – Create Resources for Cost Monitoring

## 4. Login to Azure

Open:

https://portal.azure.com

Open Azure Cloud Shell and select Bash.

Alternatively, use your Linux Azure VM with Azure CLI.

```bash
az login
```

Check subscription:

```bash
az account show -o table
```

Get subscription ID:

```bash
SUB_ID=$(az account show --query id -o tsv)

echo $SUB_ID
```

## 5. Create Resource Group

```bash
az group create \
  --name rg-cost-demo \
  --location centralindia \
  --tags Environment=Training Owner=DevOps Project=CostManagement
```

Create two additional resource groups for comparison:

```bash
az group create \
  --name rg-cost-dev \
  --location centralindia
```

```bash
az group create \
  --name rg-cost-prod \
  --location centralindia
```

## 6. Create Resources to Generate Cost Data

Create a small VM for demonstration:

```bash
az vm create \
  --resource-group rg-cost-demo \
  --name vm-cost-demo \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys
```

Create a Storage Account:

```bash
STG="costdemo$(date +%s)"

az storage account create \
  --name "$STG" \
  --resource-group rg-cost-demo \
  --location centralindia \
  --sku Standard_LRS \
  --kind StorageV2
```

Create a virtual network:

```bash
az network vnet create \
  --resource-group rg-cost-demo \
  --name vnet-cost-demo \
  --address-prefix 10.10.0.0/16 \
  --subnet-name subnet-demo \
  --subnet-prefix 10.10.1.0/24
```

We now have resources that can be explored in Cost Analysis.

**Note:** Cost data is not necessarily visible immediately. It typically takes 8–24 hours for usage and cost data to become available.

---

# PART 2 – Understand Azure Cost Management

## 7. Open Cost Management

In Azure Portal:

1. Search for Cost Management + Billing.
2. Open Cost Management.
3. Select the Azure subscription.
4. Open Cost Management.

Explore these sections:

| Feature | Purpose |
|---|---|
| Cost Analysis | Analyze spending |
| Budgets | Define spending limits |
| Cost Alerts | Monitor cost notifications |
| Exports | Export cost data |
| Advisor | Get cost-saving recommendations |
| Reservations | Review reservation utilization |
| Cost Details | Investigate individual charges |

### Teaching point

Azure Cost Management helps answer:

- How much money did we spend?
- Which resource group consumed the most?
- Which Azure service is expensive?
- What will our estimated monthly spending be?
- Are we exceeding our budget?
- Where can we reduce costs?

---

# PART 3 – Cost Analysis Practical

## 8. Explore Cost Analysis

Navigate:

```text
Azure Portal
    |
    +-- Cost Management + Billing
            |
            +-- Cost Management
                    |
                    +-- Cost Analysis
```

Select your subscription.

### Demo 1: Analyze Cost by Service

1. Open Cost Analysis.
2. Select the appropriate date range.
3. Select Group by.
4. Choose Service name.

Observe services such as:

- Virtual Machines
- Storage Accounts
- Virtual Network
- Bandwidth
- Azure Monitor

### Demo 2: Analyze Cost by Resource Group

Select:

```text
Group by → Resource group
```

Observe which resource group has consumed the most money.

### Demo 3: Analyze Cost by Location

Select:

```text
Group by → Location
```

This helps understand regional spending.

### Demo 4: Analyze Cost by Resource

Select:

```text
Group by → Resource
```

Identify the resources contributing to the total cost.

### Demo 5: Change Chart Type

Explore:

- Column chart
- Line chart
- Area chart
- Table

### Demo 6: Forecast

In Cost Analysis, explore the Forecast view.

Understand the difference:

| Actual Cost | Forecasted Cost |
|---|---|
| Cost already incurred | Estimated future cost |
| Based on reported usage | Based on historical spending trends |
| Used for actual alerts | Used for early warnings |

**Classroom exercise:** Compare cost by service, resource group, and resource.

---

# PART 4 – Create a Subscription-Level Budget

## 9. What Is an Azure Budget?

An Azure Budget is a spending threshold that helps organizations monitor their Azure consumption.

For example:

Suppose your organization has allocated ₹10,000 per month.

You want notifications when spending reaches:

- 50% – ₹5,000
- 75% – ₹7,500
- 90% – ₹9,000
- 100% – ₹10,000

We can configure these thresholds using Azure Budgets.

**Important:** A budget does not automatically stop Azure resources or prevent additional charges. It generates alerts when configured conditions are met.

## 10. Create a Budget from Azure Portal

Navigate:

```text
Cost Management + Billing
        |
        +-- Cost Management
                |
                +-- Budgets
```

Select the correct subscription.

Click:

```text
+ Add
```

Configure:

| Setting | Value |
|---|---|
| Budget name | Monthly-Subscription-Budget |
| Reset period | Monthly |
| Budget amount | 10000 |
| Start date | Current billing/calendar period |
| Expiration date | Future date |

Use your subscription's billing currency. The example amount is illustrative.

Click Next.

## 11. Configure Actual Cost Alerts

Create these thresholds:

| Threshold | Budget percentage | Example amount |
|---|---:|---:|
| Alert 1 | 50% | 5,000 |
| Alert 2 | 75% | 7,500 |
| Alert 3 | 90% | 9,000 |
| Alert 4 | 100% | 10,000 |

For each threshold:

1. Select Actual.
2. Enter the threshold percentage.
3. Add your notification email address.

Example:

```text
admin@yourdomain.com
```

Click Create.

### Expected result

When the actual cost crosses a configured threshold, Azure sends an email notification to the configured recipients.

---

# PART 5 – Forecasted Budget Alerts

## 12. Configure Forecasted Cost Alerts

Forecasted alerts help us identify whether spending is likely to exceed the budget.

Example:

Monthly budget = ₹10,000.

Suppose Azure predicts that spending will reach ₹12,000 by the end of the month.

The forecasted cost is above the budget.

### Configuration

Navigate:

```text
Cost Management
    |
    +-- Budgets
        |
        +-- Monthly-Subscription-Budget
            |
            +-- Edit
```

Open the alert configuration.

Add a forecasted threshold.

Example:

```text
Alert Type: Forecasted
Threshold: 80%
Email: admin@yourdomain.com
```

Save the budget.

### Understand the difference

| Actual alert | Forecasted alert |
|---|---|
| Notifies after actual spending crosses a threshold | Notifies when projected spending crosses a threshold |
| Reactive monitoring | Proactive monitoring |
| Based on accrued cost | Based on forecast |

**Classroom example:** If you have spent ₹6,000 but Azure predicts ₹12,000 by month-end, a forecasted alert can help you take action before the actual budget is exhausted.

---

# PART 6 – Create a Resource Group-Level Budget

## 13. Why Resource Group Budgets?

Suppose an organization has three teams:

- Development
- Testing
- Production

Each team has a separate resource group.

We want independent budgets for each team.

Example:

| Resource Group | Monthly budget |
|---|---:|
| rg-cost-dev | 5,000 |
| rg-cost-demo | 3,000 |
| rg-cost-prod | 20,000 |

### Create the development budget

1. Open Resource Groups.
2. Select rg-cost-dev.
3. Open Cost Management.
4. Select Budgets.
5. Click Add.
6. Enter the budget name.

```text
Development-Budget
```

Set amount:

```text
5000
```

Configure actual and forecasted alerts.

Repeat for the other resource groups.

### Teaching point

Subscription budgets monitor the overall subscription.

Resource Group budgets help track spending for a particular workload, application, or team.

---

# PART 7 – Cost Anomaly Detection

## 14. What Is Cost Anomaly Detection?

Cost anomaly detection identifies unexpected changes in Azure spending.

Example:

Normally, your application consumes ₹200 per day.

Suddenly, it consumes ₹2,000 per day.

Azure can identify unusual spending patterns and notify you.

### Configure Anomaly Alerts

Navigate:

```text
Cost Management
    |
    +-- Cost Alerts
        |
        +-- Add
```

Select:

```text
Alert Type: Anomaly
```

Configure the notification details and create the alert.

### View Anomalies

Navigate:

```text
Cost Management
    |
    +-- Cost Analysis
        |
        +-- Smart Views
```

Select your subscription and explore anomaly insights.

### Practical discussion

Ask students:

1. Why might Azure spending suddenly increase?
2. Could an oversized VM cause increased costs?
3. Can an unexpected data transfer increase costs?
4. Could a forgotten resource cause additional charges?

**Important:** Anomaly detection is subscription-level and relies on historical usage. It needs time to establish a usage baseline.

---

# PART 8 – Scheduled Cost Alerts

## 15. Create Scheduled Cost Reports

Sometimes administrators need regular cost reports without manually opening Azure Portal.

Azure Cost Management supports scheduled alerts based on saved Cost Analysis views.

### Practical

1. Open Cost Analysis.
2. Select the subscription.
3. Select a date range.
4. Group by Resource Group.
5. Save the view.
6. Select Subscribe.
7. Configure the reporting schedule.

Choose an available frequency:

- Daily
- Weekly
- Monthly

Configure recipient email addresses.

### Expected result

Recipients receive scheduled cost reports based on the saved Cost Analysis view.

This is useful for:

- Monthly finance reports.
- Weekly DevOps spending reports.
- Project cost monitoring.
- Management reporting.

---

# PART 9 – Export Cost Data to Azure Storage

## 16. Why Export Cost Data?

Organizations may need historical cost information for:

- Power BI dashboards.
- Financial reporting.
- Excel analysis.
- Internal audit.
- Long-term cost tracking.

We can export Azure cost details to an Azure Storage Account.

## 17. Create Storage Account

If you have not already created one, use the Storage Account created in Part 1.

Open:

```text
Azure Portal
    |
    +-- Storage Accounts
        |
        +-- Your Storage Account
```

Create a container:

```text
cost-reports
```

## 18. Configure Cost Export

Navigate:

```text
Cost Management
    |
    +-- Exports
        |
        +-- Create
```

Configure:

| Setting | Value |
|---|---|
| Export name | Monthly-Cost-Export |
| Dataset | Cost and usage details |
| Granularity | Daily |
| Export type | Actual cost |
| File format | CSV |
| Storage account | Your storage account |
| Container | cost-reports |

Choose the appropriate schedule, such as daily.

Save the export.

### Verify Export

Navigate:

```text
Storage Account
    |
    +-- Data Storage
        |
        +-- Containers
            |
            +-- cost-reports
```

Wait for the scheduled export to execute.

Download the CSV file and open it in Excel.

Explore columns such as:

- Resource ID
- Resource Group
- Service Name
- Meter Category
- Quantity
- Cost
- Currency

### Teaching point

Cost Analysis is useful for interactive analysis.

Cost Exports are useful for automated data extraction and external reporting.

---

# PART 10 – Azure Advisor Cost Optimization

## 19. What Is Azure Advisor?

Azure Advisor analyzes your Azure environment and provides recommendations to improve:

1. Cost
2. Security
3. Reliability
4. Operational Excellence
5. Performance

### Open Azure Advisor

Navigate:

```text
Azure Portal
    |
    +-- Advisor
```

Select:

```text
Cost
```

Explore recommendations such as:

- Right-size or shut down underutilized VMs.
- Delete unused resources.
- Optimize virtual machine spending.
- Review idle resources.
- Evaluate Azure reservations and savings plans.

### Practical Exercise

1. Create a VM.
2. Observe its resource configuration.
3. Explore Advisor recommendations.
4. Discuss VM resizing.
5. Discuss the difference between stopping and deallocating a VM.

**Important:** Stopping a VM from inside its operating system may not stop compute billing. Deallocating the VM releases compute resources, although disks and other associated resources may continue to incur charges.

---

# PART 11 – Action Groups and Automated Cost Response

## 20. What Is an Azure Action Group?

An Action Group is a reusable collection of notification and automation actions used by Azure Monitor and supported alerting services.

Examples:

- Email notification.
- SMS notification.
- Azure Function.
- Logic App.
- Webhook.
- Automation Runbook.

### Create an Action Group

Navigate:

```text
Azure Portal
    |
    +-- Monitor
        |
        +-- Alerts
            |
            +-- Action Groups
                |
                +-- Create
```

Configure:

| Setting | Value |
|---|---|
| Resource Group | rg-cost-demo |
| Action Group Name | ag-cost-alert |
| Display Name | CostAlert |

Select Notifications:

```text
Notification Type: Email/SMS message/Push/Voice
Name: AdminNotification
Email: admin@yourdomain.com
```

Complete the creation.

## 21. Connect Action Group to a Budget

For supported subscription and resource-group budgets:

1. Open Cost Management.
2. Open Budgets.
3. Edit your budget.
4. Open alert configuration.
5. Select the appropriate action group, where available.
6. Save.

### Advanced Automation Demo

Consider this scenario:

Your monthly budget reaches 90%.

Azure sends a budget alert.

The Action Group triggers an Azure Logic App or Automation Runbook.

The automation can:

1. Send a notification to the DevOps team.
2. Create an incident ticket.
3. Identify non-production VMs.
4. Request approval.
5. Deallocate approved non-production VMs.

**Important:** Budget notifications do not automatically stop resources. Automation must be separately designed, authorized, and tested. Do not automatically shut down production resources based only on a budget threshold.

---

# PART 12 – Azure Cost Management RBAC

## 22. Important Roles

| Role | Purpose |
|---|---|
| Owner | Full resource and access management |
| Contributor | Manage Azure resources |
| Reader | View Azure resources |
| Cost Management Reader | View cost information |
| Cost Management Contributor | Manage budgets, exports and cost configurations |

### Practical

Open:

```text
Subscription
    |
    +-- Access Control (IAM)
        |
        +-- Add Role Assignment
```

Assign:

```text
Cost Management Reader
```

to a reporting user.

Ask the student to log in using that account.

Verify that the user can view cost information but cannot manage budgets.

Next, assign:

```text
Cost Management Contributor
```

Verify that the user can manage budgets and exports.

**Teaching point:** Use Cost Management Contributor instead of Owner when the user only needs to manage cost configurations.

---

# PART 13 – AZ-104 Revision: Important Concepts

## 23. Cost Management Feature Comparison

| Feature | What it does |
|---|---|
| Cost Analysis | Analyzes current and historical costs |
| Budgets | Defines spending thresholds |
| Actual Alerts | Notifies when accrued cost crosses a threshold |
| Forecasted Alerts | Warns about projected overspending |
| Anomaly Detection | Detects unusual spending patterns |
| Scheduled Alerts | Sends recurring cost reports |
| Cost Exports | Exports cost data to storage |
| Azure Advisor | Recommends cost optimization |
| Action Groups | Sends notifications or triggers supported automation |

## 24. Important Exam Questions

**Q1. Does Azure Budget stop resources automatically?**

No. A budget generates alerts. You need separate automation to stop or deallocate resources.

**Q2. What is the difference between Cost Analysis and Budgets?**

Cost Analysis is used to investigate and analyze spending. Budgets are used to monitor spending against predefined thresholds.

**Q3. What is the difference between actual and forecasted alerts?**

Actual alerts are triggered based on accrued spending. Forecasted alerts are triggered when projected spending crosses the configured threshold.

**Q4. What is Azure Cost Anomaly Detection?**

It identifies unexpected changes in cost patterns.

**Q5. Can we create a budget for a Resource Group?**

Yes. Azure supports budgets at subscription and resource-group scopes, among other supported Cost Management scopes.

**Q6. Can we export cost information to Storage Accounts?**

Yes. Scheduled exports can store cost and usage data in Azure Storage.

**Q7. What is the purpose of Azure Advisor?**

It provides recommendations to improve cost, security, reliability, performance and operational excellence.

**Q8. What is the purpose of an Action Group?**

It defines actions such as email notifications, webhooks, Logic Apps and automation when a supported alert is triggered.

**Q9. Which RBAC role can manage Azure budgets and exports?**

Cost Management Contributor.

**Q10. Does deleting a VM remove all Azure costs?**

No. Associated disks, snapshots, public IPs and other resources may continue to incur charges.

---

# PART 14 – Student Practical Assignment

## 25. Complete the Following Tasks

- [ ] Create a Resource Group named rg-cost-lab.
- [ ] Create a Linux VM.
- [ ] Create a Storage Account.
- [ ] Explore Cost Analysis.
- [ ] Analyze costs by service.
- [ ] Analyze costs by Resource Group.
- [ ] Create a subscription-level budget.
- [ ] Configure 50%, 75%, 90% and 100% actual alerts.
- [ ] Configure a forecasted alert.
- [ ] Create a Resource Group budget.
- [ ] Explore cost anomaly detection.
- [ ] Create a scheduled cost report.
- [ ] Export cost data to an Azure Storage container.
- [ ] Explore Azure Advisor recommendations.
- [ ] Create an Action Group.
- [ ] Explain how automated cost remediation works.

## 26. Expected Learning Outcome

After completing this practical, students should be able to:

- Monitor Azure spending.
- Understand cost by service, resource and resource group.
- Create and configure Azure Budgets.
- Configure actual and forecasted alerts.
- Identify unusual cost patterns.
- Export cost information.
- Use Azure Advisor recommendations.
- Configure Action Groups.
- Apply RBAC to cost management.
- Explain automated cost optimization.

---

# 27. Cleanup

Delete the demo resource groups after the practical.

```bash
az group delete \
  --name rg-cost-demo \
  --yes \
  --no-wait
```

```bash
az group delete \
  --name rg-cost-dev \
  --yes \
  --no-wait
```

```bash
az group delete \
  --name rg-cost-prod \
  --yes \
  --no-wait
```

Check:

```bash
az group list -o table
```

**Remember:** Budgets, exports, alerts and other subscription-level configurations may need separate cleanup. Deleting the resource group does not necessarily delete subscription-level Cost Management configurations.

---

# 28. Official Microsoft Documentation

1. [Overview of Azure Cost Management](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/overview-cost-management)

2. [Create and Manage Azure Budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets)

3. [Cost Alerts](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-alerts-monitor-usage-spending)

4. [Identify Cost Anomalies](https://learn.microsoft.com/en-us/azure/cost-management-billing/understand/analyze-unexpected-charges)

5. [Understand Cost Management Scopes](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-work-scopes)

6. [Azure Cost Management Exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports)

7. [Azure Advisor](https://learn.microsoft.com/en-us/azure/advisor/advisor-overview)

8. [Azure Monitor Action Groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)

---

## Final AZ-104 Exam Tip

Remember this flow:

**Cost Analysis → Understand spending**

**Budget → Define spending limit**

**Actual Alert → Detect spending threshold crossed**

**Forecast Alert → Predict overspending**

**Anomaly Detection → Detect unusual spending**

**Cost Export → Store cost information**

**Azure Advisor → Optimize Azure resources**

**Action Group → Notify or automate a response**