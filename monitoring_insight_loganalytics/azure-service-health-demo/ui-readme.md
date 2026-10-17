# Azure Service Health Demo: Setup in the Azure Portal

This guide creates the same resources as `setup.sh` and `main.bicep`, using only the Azure Portal (https://portal.azure.com). Use it if you'd rather click through the setup than run the CLI, or if you want to show students where each setting lives.

**What you'll end up with**

| Resource | Name | Scope it watches |
|---|---|---|
| Resource group | `rg-servicehealth-demo` | n/a |
| Action group | `ag-servicehealth-demo` | n/a (sends email) |
| Service Health alert | `alert-servicehealth-servicehealth-demo` | Whole subscription |
| Resource Health alert | `alert-resourcehealth-servicehealth-demo` | The demo resource group |
| Demo VM (optional) | `vm-health-demo` | Used to trigger a Resource Health alert |

**Time:** about 15 minutes (plus about 5 minutes for the VM).
**Permissions:** Contributor (or Monitoring Contributor plus Contributor on the resource group) on the subscription.

---

## 1. Confirm your subscription

1. Sign in to the portal.
2. In the top search bar, type **Subscriptions** and open it.
3. Note the subscription you'll use. Every step below must use this same subscription.

## 2. Register resource providers

*(CLI equivalent: `az provider register`. These are usually already registered, so this step is only a quick check.)*

1. Open **Subscriptions** and select your subscription.
2. In the left menu, under **Settings**, select **Resource providers**.
3. Search for `Microsoft.Insights`. If the status is not **Registered**, select it and click **Register**.
4. Do the same for `Microsoft.ResourceHealth`.
5. Wait until both show **Registered**. You may need to click **Refresh**.

> The CLI script also installs the `resource-graph` extension. You don't need that in the portal, because **Resource Graph Explorer** is built in.

## 3. Create the resource group

1. Search for **Resource groups** and click **+ Create**.
2. Fill in:
   - **Subscription:** your subscription
   - **Resource group:** `rg-servicehealth-demo`
   - **Region:** `(Asia Pacific) Central India`
3. Click **Review + create**, then **Create**.

## 4. Create the action group

1. Search for **Monitor** and open it.
2. Select **Alerts**, then **Action groups** in the top toolbar, then **+ Create**.
3. On the **Basics** tab, fill in:
   - **Subscription:** your subscription
   - **Resource group:** `rg-servicehealth-demo`
   - **Region:** `Global`
   - **Action group name:** `ag-servicehealth-demo`
   - **Display name:** `svchealth` (12 characters maximum)
4. On the **Notifications** tab, fill in:
   - **Notification type:** `Email/SMS message/Push/Voice`
   - **Name:** `demo-email`
   - In the side panel, tick **Email** and enter your alert email address. Click **OK**.
5. Leave the **Actions** tab empty.
6. On the **Review + create** tab, find **Enable the common alert schema** (shown either here or in the email panel). Set it to **Yes**.
7. Click **Create**.

✅ You should receive an email within a few minutes saying you were added to `ag-servicehealth-demo`.

## 5. Create the Service Health alert (subscription scope)

This alert fires for incidents, maintenance, advisories and security events in the selected regions.

1. Search for **Service Health** and open it.
2. In the left menu, select **Health alerts**, then **+ Create service health alert**.
3. On the **Condition** tab, fill in:
   - **Subscription:** your subscription
   - **Services:** `Select all`
   - **Regions:** `Central India`, `South India`, `Global`
   - **Event types:** tick all four:
     - **Service issue** (in the template, `Incident`)
     - **Planned maintenance** (`Maintenance`)
     - **Health advisories** (`Informational` and `ActionRequired`)
     - **Security advisory** (`Security`)
4. On the **Actions** tab, click **Select action groups** and choose `ag-servicehealth-demo`.
5. On the **Details** tab, fill in:
   - **Resource group:** `rg-servicehealth-demo`
   - **Alert rule name:** `alert-servicehealth-servicehealth-demo`
   - **Alert rule description:** `Demo: notify on Azure Service Health events affecting the selected regions.`
   - **Region:** `Global`
   - Tick **Enable alert rule upon creation**.
6. Click **Review + create**, then **Create**.

> **Teaching point:** the alert rule is *stored* in the demo resource group, but it *watches* the whole subscription. Service Health events are always reported at subscription level.

## 6. Create the Resource Health alert (resource group scope)

This alert fires when any resource in the demo resource group becomes **Degraded** or **Unavailable**. It doesn't matter whether Azure caused it or a user did.

1. Open **Monitor**, select **Alerts**, then click **+ Create** and choose **Alert rule**.
2. On the **Scope** tab, click **Select scope**. Filter the list to your subscription, tick `rg-servicehealth-demo` (the resource group itself, not a resource inside it), and click **Apply**.
3. On the **Condition** tab, click **See all signals**. Choose **Resource health**, then click **Apply**.
4. Set the alert logic:
   - **Event status:** leave as `All selected`
   - **Current resource status:** `Degraded`, `Unavailable`
   - **Previous resource status:** leave as `All selected`
   - **Reason type:** `Platform Initiated`, `User Initiated`
5. On the **Actions** tab, click **Select action groups** and choose `ag-servicehealth-demo`.
6. On the **Details** tab, fill in:
   - **Resource group:** `rg-servicehealth-demo`
   - **Alert rule name:** `alert-resourcehealth-servicehealth-demo`
   - **Description:** `Demo: notify when a resource in the demo resource group becomes Degraded or Unavailable.`
   - **Region:** `Global`
   - Tick **Enable upon creation**.
7. Click **Review + create**, then **Create**.

> **Shortcut:** you can also start this from **Service Health**, then **Resource health**, then **Add resource health alert**. The settings are the same.

## 7. (Optional) Deploy the demo VM

*(CLI equivalent: `DEPLOY_VM=true`.)* You need this VM only if you want to trigger a Resource Health alert live, for example by stopping the VM.

1. Search for **Virtual machines** and click **+ Create**, then choose **Azure virtual machine**.
2. On the **Basics** tab, fill in:
   - **Resource group:** `rg-servicehealth-demo`
   - **Virtual machine name:** `vm-health-demo`
   - **Region:** `(Asia Pacific) Central India`
   - **Availability options:** `No infrastructure redundancy required`
   - **Image:** `Ubuntu Server 22.04 LTS - x64 Gen2`
   - **Size:** `Standard_B1s` (click **See all sizes** if it isn't listed)
   - **Authentication type:** `SSH public key`
   - **Username:** `azureuser`
   - **SSH public key source:** `Generate new key pair`
   - **Public inbound ports:** `None`
3. On the **Networking** tab, fill in:
   - **Public IP:** `None`
   - **NIC network security group:** `None`
4. Click **Review + create**, then **Create**. When prompted, download the private key. You won't need it for the demo, but you can't download it later.

## 8. Verify

1. Open **Resource groups** and select `rg-servicehealth-demo`. Tick **Show hidden types** to see the alert rules. You should see:
   - `ag-servicehealth-demo` (Action group)
   - `alert-servicehealth-servicehealth-demo` (Activity log alert rule)
   - `alert-resourcehealth-servicehealth-demo` (Activity log alert rule)
   - VM resources (VM, disk, NIC, VNet), if you created the VM
2. Open **Monitor**, then **Alerts**, then **Alert rules**. Both rules should show as **Enabled**.
3. Check your inbox for the action group confirmation email.
4. **Wait about 5 minutes** before triggering anything live, so the rules become active.

Then continue with `DEMO-STEPS.md`.

### Useful portal locations

- **Service Health, Service issues:** https://portal.azure.com/#view/Microsoft_Azure_Health/AzureHealthBrowseBlade/~/serviceIssues
- **Monitor, Alerts:** https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/alertsV2

## 9. Cleanup

*(CLI equivalent: `./cleanup.sh`.)*

1. Open **Resource groups** and select `rg-servicehealth-demo`.
2. Click **Delete resource group**. Type the resource group name to confirm, then click **Delete**.

All the demo resources live in this resource group, so deleting it removes the action group, both alert rules and the VM. That includes the subscription-wide Service Health alert, because the rule itself is stored in the group.
