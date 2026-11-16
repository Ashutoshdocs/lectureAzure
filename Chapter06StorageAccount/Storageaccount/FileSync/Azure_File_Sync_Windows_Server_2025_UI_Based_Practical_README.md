# Azure File Sync -- Windows Server 2025 VM (UI-Based Practical)

**Practical type:** Azure Portal + Windows Server GUI\
**Audience:** Beginners learning Azure Storage and hybrid file services\
**Scenario:** Create an Azure file share, connect a Windows Server 2025
Azure VM, and demonstrate file synchronization in both directions.

------------------------------------------------------------------------

## 1. What is Azure File Sync?

Azure File Sync lets you centralize file data in an Azure file share
while keeping a local copy/cache on one or more Windows Servers.

Think of Azure Files as the central cloud file share and Windows Server
as a local file server that synchronizes a selected folder with it.

### Architecture

``` text
                 Azure subscription
                         |
                  Resource Group
                    /        \
                   /          \
        Storage Sync Service   Storage Account
                 |                  |
              Sync Group       Azure File Share
                 |                  ^
                 |                  |
             Server Endpoint -------+
                 |
       Windows Server 2025 VM
          D:\CompanyData
                 |
        Users create/edit files
```

A sync group contains one cloud endpoint (an Azure file share) and one
or more server endpoints (folders on registered Windows Servers). The
Azure file share is the hub for the sync group.

### What you will demonstrate

1.  Create an Azure Storage Account and Azure file share.
2.  Create a Windows Server 2025 VM from the Azure Portal.
3.  Install the Azure File Sync agent on the VM.
4.  Create a Storage Sync Service.
5.  Register the Windows Server with that service.
6.  Create a sync group and cloud endpoint.
7.  Add a server endpoint such as `D:\CompanyData`.
8.  Create and edit files on Windows Server.
9.  Verify that the changes reach the Azure file share.
10. Discuss cloud-to-server change detection and cloud tiering.

------------------------------------------------------------------------

## 2. Learning objectives

By the end of this lab, students should be able to:

-   Explain the difference between Azure Files and Azure File Sync.
-   Identify a Storage Sync Service, sync group, cloud endpoint, and
    server endpoint.
-   Deploy Azure File Sync with the Azure Portal.
-   Register a Windows Server 2025 machine.
-   Synchronize a local Windows folder with an Azure file share.
-   Explain initial synchronization, ongoing synchronization, and cloud
    tiering.
-   Troubleshoot common registration and synchronization problems.

------------------------------------------------------------------------

## 3. Lab design and resource names

Use these names as an example. Azure storage account names must be
globally unique and contain only lowercase letters and numbers. If a
name is unavailable, add a few digits.

  Resource                Example
  ----------------------- --------------------------------------
  Resource group          `rg-filesync-demo`
  Region                  One Azure File Sync-supported region
  Storage account         `stfilesyncdemo2025`
  Azure file share        `companydata`
  Storage Sync Service    `sss-filesync-demo`
  Sync group              `sg-companydata`
  Windows VM              `vm-fileserver-2025`
  Windows Server folder   `D:\CompanyData`

**Region rule:** Place the Storage Sync Service and the storage account
containing the Azure file share in the same Azure region. Check Azure
File Sync region availability before selecting the region.

For a classroom lab, use one region for the VM, Storage Account, and
Storage Sync Service where practical. This reduces latency and makes the
architecture easier to explain.

------------------------------------------------------------------------

## 4. Prerequisites

-   An Azure subscription with permission to create VMs, storage
    resources, and Storage Sync Services.
-   Permission to assign or verify Azure RBAC roles.
-   A Windows Server 2025 VM with a supported edition.
-   Internet connectivity from the VM to Azure over outbound HTTPS (TCP
    443).
-   A browser with access to the Azure Portal.
-   A suitable VM size and disk capacity for the demo data.

### Important compatibility notes

-   Windows Server 2025 is supported by Azure File Sync according to
    Microsoft's current planning documentation.
-   Install the current Azure File Sync agent version from the Microsoft
    Download Center.
-   The agent requires .NET Framework 4.7.2 or later. Windows Server
    2019 and later include this by default.
-   Azure File Sync requires an Azure file share in a supported
    configuration. For this practical, use a standard SMB Azure file
    share in a StorageV2 (general-purpose v2) storage account.
-   Do not assume every Azure Files account/share model is compatible
    with Azure File Sync. Check the current support matrix before using
    a provisioned v2 share or a specialized account model in production.
-   Keep the Storage Account key access setting enabled where required
    by the current Azure File Sync prerequisites. Follow your
    organization's security policy.
-   Azure File Sync requires compatible SMB security settings, including
    SMB 3.1.1, NTLM v2, and AES-128-GCM where applicable. Review the
    storage account SMB security settings if cloud endpoint creation
    fails.

------------------------------------------------------------------------

## 5. Part A -- Create the Resource Group

1.  Sign in to the [Azure Portal](https://portal.azure.com).
2.  Search for **Resource groups**.
3.  Select **Create**.
4.  Select your subscription.
5.  Enter resource group name: `rg-filesync-demo`.
6.  Select your chosen region.
7.  Select **Review + create**.
8.  Select **Create**.

**Teaching note:** A resource group is a logical management container.
It does not itself provide file synchronization.

------------------------------------------------------------------------

## 6. Part B -- Create the Storage Account

1.  In the Azure Portal, search for **Storage accounts**.
2.  Select **Create**.
3.  On the Basics tab:
    -   Subscription: your lab subscription.
    -   Resource group: `rg-filesync-demo`.
    -   Storage account name: `stfilesyncdemo2025` (or a unique
        alternative).
    -   Region: the region selected for the Storage Sync Service.
    -   Performance: **Standard**.
    -   Redundancy: **Locally-redundant storage (LRS)** for a low-cost
        classroom lab, if available.
4.  Keep the account type as **StorageV2 (general-purpose v2)**.
5.  Review the remaining tabs. Keep public access disabled unless you
    have a specific reason to change it.
6.  Select **Review**, then **Create**.
7.  Wait for deployment to finish and open the storage account.

### Check account configuration

1.  In the storage account, open **Configuration** under Settings.
2.  Check that **Allow storage account key access** is enabled if
    required by the Azure File Sync prerequisites.
3.  Save changes if you changed the setting.

Do not share the storage account key with students or place it in
scripts, screenshots, or source control.

------------------------------------------------------------------------

## 7. Part C -- Create the Azure File Share

1.  Open the storage account.
2.  Under **Data storage**, select **File shares**.
3.  Select **+ File share**.
4.  Name it `companydata`.
5.  Choose an appropriate access tier and quota for the lab. For a small
    classroom demo, use a low quota appropriate to the available
    options.
6.  Select **Create**.
7.  Open the new `companydata` share.

At this point, the Azure file share is empty. It will become the cloud
endpoint for the sync group.

**Explain to students:** Azure Files is the cloud file share. Azure File
Sync is the synchronization service that connects this share to Windows
Server folders.

------------------------------------------------------------------------

## 8. Part D -- Create the Windows Server 2025 Azure VM

1.  In the Azure Portal, search for **Virtual machines**.
2.  Select **Create** → **Azure virtual machine**.
3.  On the Basics tab, enter:
    -   Resource group: `rg-filesync-demo`.
    -   Virtual machine name: `vm-fileserver-2025`.
    -   Region: same region as the storage resources, where practical.
    -   Image: **Windows Server 2025 Datacenter** (or another supported
        Windows Server 2025 edition).
    -   Size: choose a small supported size suitable for the lab.
    -   Administrator username: choose a lab administrator account.
    -   Password: use a strong unique password.
4.  Under inbound port rules, allow **RDP (3389)** only from your own
    public IP or through a secure access method such as Azure Bastion.
    Do not expose RDP to the entire internet.
5.  On the Disks tab, retain the OS disk and add a separate data disk if
    you want to use the exact `D:\CompanyData` example.
    -   Select **Create and attach a new disk**.
    -   Choose a small disk size suitable for the lab.
    -   Save the disk configuration.
6.  Review Networking and Management settings.
7.  Select **Review + create**, then **Create**.
8.  Wait for the VM deployment to complete.

### Initialize the data disk (if added)

1.  Open the VM's **Connect** page and connect using RDP or Azure
    Bastion.
2.  On Windows Server, open **Server Manager** → **Tools** → **Computer
    Management**.
3.  Select **Disk Management**.
4.  If the new disk is offline, bring it online.
5.  Initialize the disk using GPT.
6.  Create a **New Simple Volume**.
7.  Assign drive letter `D:` if it is available.
8.  Format it as NTFS and give it a label such as `Data`.
9.  Finish the wizard.

If you did not add a data disk, use a folder on another suitable data
volume. Avoid using the system volume for this lab if you want to
demonstrate cloud tiering later, because server endpoints on the system
volume cannot use cloud tiering.

### Create the local sync folder

1.  Open File Explorer.
2.  Open `D:`.
3.  Create a folder named `CompanyData`.

The final folder path should be:

``` text
D:\CompanyData
```

Do not move or change this server endpoint path or its drive letter
after creating the endpoint.

------------------------------------------------------------------------

## 9. Part E -- Download and install the Azure File Sync agent

The Azure File Sync agent is installed on Windows Server. It monitors
the server endpoint and communicates with Azure File Sync.

1.  From the Windows Server VM, open Microsoft Edge.
2.  Visit the official [Azure File Sync agent download
    page](https://learn.microsoft.com/en-us/azure/storage/file-sync/file-sync-release-notes).
3.  Follow the current download link to the Microsoft Download Center
    and download the latest supported agent for your server.
4.  Run the downloaded installer as an administrator.
5.  Accept the license terms.
6.  Continue through the installation wizard using the recommended
    options.
7.  Complete installation. Restart the server if the installer requests
    it.

**Important:** Download the agent only from Microsoft. Do not use an old
agent installer saved from a previous class.

### Optional: Check installed services

On the server, open **Services** (`services.msc`) and look for the Azure
File Sync service components. The primary sync service is commonly shown
as **Storage Sync Agent** / `FileSyncSvc`, depending on the installed
agent version.

------------------------------------------------------------------------

## 10. Part F -- Create the Storage Sync Service in Azure

1.  Return to the Azure Portal.
2.  Search for **Storage Sync Services** or **Azure File Sync**.
3.  Select **Create**.
4.  Enter:
    -   Subscription: your lab subscription.
    -   Resource group: `rg-filesync-demo`.
    -   Storage Sync Service name: `sss-filesync-demo`.
    -   Region: same region as the storage account containing
        `companydata`.
5.  Select **Review + create**.
6.  Select **Create**.
7.  Open the deployed Storage Sync Service.

**Teaching note:** The Storage Sync Service is the Azure management
resource that establishes the trust relationship with registered Windows
Servers and manages sync groups.

------------------------------------------------------------------------

## 11. Part G -- Register Windows Server 2025

Registration connects the Windows Server to the Storage Sync Service.

1.  On the Windows Server VM, open the **Azure File Sync Agent**
    application from the Start menu.
2.  Select **Server Registration** if it is not already open.
3.  Sign in using an Azure account that has the required permissions.
4.  Select the correct tenant and subscription if prompted.
5.  Select the Storage Sync Service:
    -   Resource group: `rg-filesync-demo`.
    -   Storage Sync Service: `sss-filesync-demo`.
6.  Select **Register**.
7.  Complete the wizard and wait for confirmation.

### Verify registration in Azure

1.  In the Azure Portal, open `sss-filesync-demo`.
2.  Select **Registered servers**.
3.  Confirm that `vm-fileserver-2025` appears.
4.  Check that the server is online/healthy.

If the VM does not appear, check outbound connectivity, sign-in account,
subscription, tenant, permissions, and agent installation.

**Permissions:** The person registering the server and creating the
cloud endpoint needs appropriate Azure roles. At minimum, use the Azure
File Sync Administrator role or a suitable Owner/Contributor assignment
on the Storage Sync Service. Cloud endpoint creation also needs the
required storage-account permissions; storage-account read-only access
alone is not sufficient.

------------------------------------------------------------------------

## 12. Part H -- Create the Sync Group and Cloud Endpoint

A sync group defines which server folders synchronize with which Azure
file share.

1.  In the Azure Portal, open `sss-filesync-demo`.
2.  Select **Sync groups**.
3.  Select **+ Add sync group**.
4.  Enter sync group name: `sg-companydata`.
5.  Select the subscription.
6.  Select storage account: `stfilesyncdemo2025`.
7.  Select Azure file share: `companydata`.
8.  Select **Create**.

The Azure file share is added as the **cloud endpoint**. Open the sync
group and verify that the cloud endpoint is visible.

If the cloud endpoint is not created, review the error and check the
account configuration and permissions. You may need to add the cloud
endpoint manually from the sync group page.

**Teaching note:** - Cloud endpoint = Azure file share. - Server
endpoint = local folder on a registered Windows Server. - Sync group =
the relationship that keeps the endpoints synchronized.

------------------------------------------------------------------------

## 13. Part I -- Add the Server Endpoint

1.  Open `sss-filesync-demo`.
2.  Select **Sync groups** → `sg-companydata`.
3.  Under **Server endpoints**, select **+ Add server endpoint**.
4.  Configure:
    -   Registered server: `vm-fileserver-2025`.
    -   Path: `D:\CompanyData`.
    -   Cloud tiering: **Disabled** for the first classroom
        demonstration.
5.  Select **Create**.
6.  Wait for the endpoint to be created and initial synchronization to
    begin.
7.  Refresh the sync group and inspect the server endpoint status.

### Why disable cloud tiering initially?

For the first practical, students should see actual file contents stored
locally on the Windows Server and in Azure Files. Cloud tiering is a
separate feature that can replace less frequently used local file
content with cloud-backed tiered files while retaining the namespace.

Cloud tiering should only be enabled after students understand normal
synchronization. Do not enable it on the system volume for this lab.

------------------------------------------------------------------------

## 14. Part J -- Live classroom demo: Create and edit files on Windows Server

This is the key demonstration. The instructor should keep the Windows
Server VM and Azure Portal open side by side.

### Demo 1: Create a file on Windows Server

1.  Connect to `vm-fileserver-2025`.
2.  Open File Explorer → `D:\CompanyData`.
3.  Create a folder named `HR`.
4.  Inside `HR`, create a text file named `EmployeePolicy.txt`.
5.  Enter this content:

``` text
COMPANY EMPLOYEE POLICY
Version: 1.0

1. Employees must protect company information.
2. Do not share passwords.
3. Report suspicious activity to IT.
```

6.  Save the file.
7.  Wait for synchronization to complete.

### Verify in Azure Portal

1.  Open the storage account `stfilesyncdemo2025`.
2.  Select **File shares** → `companydata`.
3.  Open the `HR` folder.
4.  Confirm that `EmployeePolicy.txt` appears.
5.  Download or preview the file, where the portal experience permits,
    and verify its content.

**Explain:** The local server endpoint detected the new file and
synchronized it to the cloud endpoint.

### Demo 2: Edit an existing file on Windows Server

1.  Return to the Windows Server VM.
2.  Open `D:\CompanyData\HR\EmployeePolicy.txt`.
3.  Add this line:

``` text
4. Updated during the Azure File Sync classroom demonstration.
```

4.  Save the file.
5.  Wait for synchronization.
6.  Refresh the Azure file share view.
7.  Download the file or inspect its content to verify the updated line.

### Demo 3: Create another file and folder

On Windows Server, create:

``` text
D:\CompanyData\Finance\MonthlyReport.txt
```

Add sample content:

``` text
MONTHLY FINANCE REPORT
Month: November 2026
Status: Classroom demonstration
```

Save it and verify that the `Finance` folder and file appear in the
Azure file share.

### What students should observe

  -----------------------------------------------------------------------
  Action on Windows Server            Expected result in Azure Files
  ----------------------------------- -----------------------------------
  Create a folder                     Folder appears in the cloud
                                      endpoint

  Create a text file                  File appears in the cloud endpoint

  Edit and save a file                Cloud copy is updated

  Create another folder/file          New namespace and file content
                                      synchronize
  -----------------------------------------------------------------------

Synchronization is asynchronous. Do not promise that every change
appears instantly. The first synchronization can take longer depending
on the number and size of files, network bandwidth, and server
performance.

------------------------------------------------------------------------

## 15. Part K -- Demonstrate a change made in Azure Files

This is useful for teaching the difference between server-side change
monitoring and cloud-side change detection.

1.  In Azure Portal, open the `companydata` file share.
2.  Upload a small text file such as `CloudCreated.txt` into the root of
    the share, if the portal upload experience is available.
3.  Explain that a change made directly in the cloud endpoint is not
    necessarily discovered immediately by the server.
4.  Azure File Sync runs cloud change detection periodically; the
    documented default behavior is that a cloud endpoint change
    detection job starts once every 24 hours.
5.  Therefore, do not use a portal upload as proof of immediate two-way
    synchronization during a short class.

### How to make the reverse-direction demo more predictable

For a classroom demonstration, use one of these approaches:

-   **Recommended:** Create and edit files on the Windows Server and
    verify them in Azure Files. This is the reliable core demo.
-   For a cloud-to-server test, allow time for cloud change detection
    and verify later.
-   For a controlled test, an administrator can trigger cloud endpoint
    change detection using the supported Azure File Sync PowerShell
    cmdlets. This is an optional command-line extension, not part of the
    UI-only core lab. Check the current Microsoft documentation for the
    exact cmdlet and parameters before using it.

After the cloud change is detected, check the corresponding folder on
`D:\CompanyData`.

**Important:** Avoid editing the same file on the server and in Azure
Files at the same time. Concurrent edits can create conflicts or
conflict copies. Demonstrate one change at a time.

------------------------------------------------------------------------

## 16. Part L -- Understand Cloud Tiering (Optional extension)

Cloud tiering helps reduce local storage consumption.

-   Frequently accessed files can remain fully cached on the Windows
    Server.
-   Infrequently accessed file content can be tiered to Azure Files.
-   The file and folder namespace remains visible locally.
-   When a user opens a tiered file, Azure File Sync recalls the file
    content from Azure.

### Optional instructor explanation

In the Add server endpoint configuration, cloud tiering offers policies
such as:

-   **Volume free space policy:** Keep a configured amount of free space
    on the server volume.
-   **Date policy:** Tier files that have not been accessed for a
    configured number of days.

For the first lab, leave cloud tiering disabled. If you run an
additional tiering exercise, use a non-system data volume, test files,
and a conservative policy. Do not assume a file is fully cached just
because its name is visible in File Explorer.

------------------------------------------------------------------------

## 17. Part M -- Monitor synchronization health

In the Azure Portal:

1.  Open the Storage Sync Service.
2.  Select **Sync groups**.
3.  Open `sg-companydata`.
4.  Inspect the cloud endpoint and server endpoint.
5.  Review sync status, health, and any errors.
6.  Open **Registered servers** and check the server status.

On Windows Server:

1.  Open **Services** and verify that the Azure File Sync service is
    running.
2.  Review Event Viewer if synchronization is not progressing.
3.  Check the Azure File Sync agent logs and telemetry using the current
    Microsoft troubleshooting guide.

### What healthy operation means

-   The server is registered.
-   The server endpoint exists.
-   The cloud endpoint points to the intended Azure file share.
-   Initial sync completes.
-   New or modified server-side files eventually appear in Azure Files.
-   No persistent sync errors are reported.

------------------------------------------------------------------------

## 18. Troubleshooting

  -----------------------------------------------------------------------
  Symptom                             What to check
  ----------------------------------- -----------------------------------
  Server does not appear in           Confirm agent installation,
  Registered servers                  registration wizard completion,
                                      tenant, subscription, permissions,
                                      and outbound HTTPS connectivity

  Registration sign-in fails          Check account access, tenant
                                      selection, browser sign-in, and
                                      organizational conditional access
                                      requirements

  Cloud endpoint creation fails       Check Storage Sync Service region,
                                      storage account region, storage
                                      account configuration, and required
                                      storage account permissions

  Server endpoint creation fails      Confirm the server is registered,
                                      the folder exists, the path is
                                      local, and the endpoint path is not
                                      already used incompatibly

  Files do not appear in Azure        Check endpoint health, agent
                                      service, initial sync progress,
                                      network connectivity, and event
                                      logs

  Cloud-side file does not appear     Remember that cloud change
  locally right away                  detection is periodic; allow time
                                      or use the supported
                                      change-detection procedure

  Sync errors or conflicts            Avoid simultaneous edits; inspect
                                      sync health and conflict
                                      information; preserve both copies
                                      before resolving

  VM cannot reach Azure               Check DNS, outbound TCP 443, NSG
                                      rules, proxy/firewall
                                      configuration, and required service
                                      endpoints

  Tiered file cannot open             Check connectivity to Azure and the
                                      Azure File Sync service; allow the
                                      recall to complete
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 19. Production considerations

1.  **Use private networking where appropriate:** Consider a private
    endpoint for the Azure file share and configure private DNS
    correctly. Plan the network path for Azure File Sync service
    communication separately.
2.  **Do not expose RDP publicly:** Use Azure Bastion, VPN, or tightly
    restricted source IPs.
3.  **Use least privilege:** Give administrators only the Azure RBAC
    permissions needed to register servers and manage endpoints.
4.  **Protect storage credentials:** Do not distribute storage account
    keys. Follow Microsoft's current authentication and security
    guidance.
5.  **Plan capacity:** Size local disks, Azure file share capacity, and
    network bandwidth based on real workloads.
6.  **Understand conflict behavior:** Multiple endpoints can modify the
    same files. Define ownership and collaboration practices.
7.  **Back up your data:** Azure File Sync is synchronization, not a
    complete backup solution. Use Azure Backup for Azure file shares and
    an appropriate backup strategy for Windows Server.
8.  **Plan disaster recovery:** Document server replacement,
    re-registration, endpoint recovery, and restore procedures.
9.  **Monitor health:** Review sync errors, server status, capacity, and
    operational alerts.
10. **Check current support limits:** Review Azure File Sync scale
    targets, supported regions, supported storage account types, and
    interoperability before production deployment.

------------------------------------------------------------------------

## 20. Student assignment

Complete the following without copying the instructor's exact file
names:

1.  Create a folder `Projects` on the Windows Server endpoint.
2.  Create `Project-A.txt` and add at least five lines.
3.  Edit the file and add a version/date line.
4.  Verify that the new file and edit appear in the Azure file share.
5.  Create a second folder named `Operations` and add a file.
6.  Capture screenshots of:
    -   Registered server in the Storage Sync Service.
    -   Sync group with cloud endpoint and server endpoint.
    -   Local Windows Server folder.
    -   Azure file share showing the synchronized folders/files.
7.  Explain why a file uploaded directly to Azure Files may not
    immediately appear on the Windows Server.
8.  Explain the purpose of cloud tiering and why it was disabled in the
    core lab.

------------------------------------------------------------------------

## 21. Interview questions

1.  What is Azure File Sync?
2.  What is the difference between Azure Files and Azure File Sync?
3.  What is a Storage Sync Service?
4.  What is a sync group?
5.  What is a cloud endpoint?
6.  What is a server endpoint?
7.  Why must the cloud endpoint's storage account be in the same region
    as the Storage Sync Service?
8.  What does the Azure File Sync agent do?
9.  How does Azure File Sync help organizations with multiple branch
    offices?
10. What is cloud tiering?
11. Does cloud tiering delete the file namespace from Windows Server?
12. Is Azure File Sync a backup solution?
13. Why might a cloud-side change take longer to appear on a registered
    server?
14. What happens if two endpoints modify the same file?
15. Which network connectivity should be checked when registration or
    synchronization fails?

------------------------------------------------------------------------

## 22. Cleanup -- Avoid ongoing Azure charges

After the classroom practical:

1.  Confirm that you no longer need the synchronized demo data.
2.  In the Storage Sync Service, remove the server endpoint from the
    sync group if you are retiring the lab.
3.  Unregister the server from the Storage Sync Service using the
    supported Azure File Sync unregister procedure.
4.  Remove the sync group and Storage Sync Service when no longer
    needed.
5.  Delete the Azure file share and storage account if they are
    dedicated to this lab.
6.  Stop and delete the Windows Server VM and its disks if they are no
    longer required.
7.  Delete the resource group `rg-filesync-demo` only after confirming
    it contains no resources you need.

**Caution:** Removing an endpoint, unregistering a server, or deleting a
storage resource can affect access to synchronized data. Confirm that
you have a separate copy of any files you want to keep before cleanup.

------------------------------------------------------------------------

## 23. Official Microsoft documentation

-   [Deploy Azure File
    Sync](https://learn.microsoft.com/azure/storage/file-sync/file-sync-deployment-guide)
-   [Plan an Azure File Sync
    deployment](https://learn.microsoft.com/azure/storage/file-sync/file-sync-planning)
-   [Azure File Sync server
    registration](https://learn.microsoft.com/azure/storage/file-sync/file-sync-server-registration)
-   [Create an Azure File Sync server
    endpoint](https://learn.microsoft.com/azure/storage/file-sync/file-sync-server-endpoint-create)
-   [Azure File Sync release notes and agent
    downloads](https://learn.microsoft.com/azure/storage/file-sync/file-sync-release-notes)
-   [Troubleshoot Azure File
    Sync](https://learn.microsoft.com/azure/storage/file-sync/file-sync-troubleshoot)

------------------------------------------------------------------------

## 24. Final classroom recap

  -----------------------------------------------------------------------
  Component                           Responsibility
  ----------------------------------- -----------------------------------
  Azure Storage Account               Hosts the Azure file share

  Azure File Share                    Central cloud file storage

  Storage Sync Service                Manages registered servers and sync
                                      groups

  Sync Group                          Defines the synchronization
                                      relationship

  Cloud Endpoint                      Azure file share in the sync group

  Server Endpoint                     Local Windows Server folder

  Azure File Sync Agent               Monitors local changes and
                                      synchronizes data

  Cloud Tiering                       Keeps less-used file content in
                                      Azure while retaining the local
                                      namespace
  -----------------------------------------------------------------------

**One-line explanation for students:** Azure File Sync keeps a Windows
Server folder synchronized with an Azure file share, allowing users to
work with local file-server data while Azure Files provides centralized
cloud storage.
