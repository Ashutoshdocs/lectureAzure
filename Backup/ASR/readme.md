# Azure Site Recovery (ASR) – Azure VM Disaster Recovery Practical

## 1. Objective

In this practical, we configure **Azure Site Recovery (ASR)** for an Azure VM running Microsoft SQL Server.

The goal is to:

- Replicate an Azure VM from a **source region** to a **target region**.
- Understand how continuous replication differs from Azure Backup.
- Configure a **Recovery Services Vault**.
- Configure target-region networking and storage.
- Monitor replication health and **Recovery Point Objective (RPO)**.
- Perform a **Test Failover**.
- Validate the recovered SQL Server VM and database.
- Clean up the test environment.
- Disable replication after testing.

The practical demonstrates disaster recovery rather than traditional backup. The source SQL VM is continuously replicated toward the recovery region.

---

# 2. Scenario

### Source environment

We have:

```text
Azure VM
   |
   +-- Microsoft SQL Server
   |
   +-- appdb
        |
        +-- log data table
```

The source VM is located in:

```text
North Europe
```

### Disaster recovery target

We want the application infrastructure to be recoverable in:

```text
West Europe
```

The instructor's practical uses North Europe → West Europe as the source/target example.

---

# 3. Architecture

```text
                 SOURCE REGION
                 North Europe
                      |
                      |
                +-------------+
                |   SQL VM    |
                |             |
                | SQL Server  |
                |   appdb     |
                +-------------+
                      |
                      |
                Continuous
                 Replication
                      |
                      v
             +-------------------+
             | Recovery Services |
             |      Vault        |
             +-------------------+
                      |
              Replicated disks
              + recovery points
                      |
                      v
                TARGET REGION
                 West Europe
                      |
              +----------------+
              | Target VNet    |
              +----------------+
                      |
              Failover creates
                  Azure VM
                      |
                      v
              +----------------+
              | SQL VM Test    |
              |                |
              | SQL Server     |
              | appdb          |
              +----------------+
```

---

# 4. Important Concept – ASR vs Backup

## Azure Backup

Backup generally follows:

```text
Production VM
      |
      v
 Backup
      |
      v
 Recovery
```

A restore operation must retrieve backup data and create/recover the workload.

## Azure Site Recovery

ASR follows:

```text
Source VM
    |
    | Continuous replication
    v
Recovery infrastructure
    |
    | Failover
    v
Target VM
```

The major advantage demonstrated in this practical is that ASR provides a much more recent recovery point.

In the demonstration, the replication health became **Healthy** and the RPO was approximately **one minute**, meaning recovery could target data roughly one minute behind the source.

---

# 5. What is RPO?

**RPO = Recovery Point Objective**

It answers:

> "How much recent data could I potentially lose if I have to recover?"

Example:

```text
Current time:       11:08
Latest RPO:         11:07

Potential data loss ≈ 1 minute
```

In the practical, the RPO initially showed 11:01 and later moved to 11:11 after replication caught up.

Therefore:

```text
Smaller RPO
     ↓
More recent recovery point
     ↓
Less potential data loss
```

---

# 6. Prerequisites

Before starting:

- Azure subscription
- Existing Azure VM
- Microsoft SQL Server installed on the VM
- SQL database available for testing
- Source VM running correctly
- Access to Azure Portal
- Permission to configure Site Recovery
- Target Azure region available

For this practical, the source workload is an Azure SQL VM containing an `appdb` database and a `log data` table.

---

# 7. Step 1 – Verify the Source SQL VM

Open the Azure Portal.

Navigate to:

```text
Virtual Machines
    ↓
SQL VM
```

Verify:

```text
VM Status       : Running
Location        : North Europe
OS Disk         : Present
Data Disk       : Present
SQL Server      : Running
```

Connect using SQL Server Management Studio.

Run:

```sql
SELECT *
FROM log_data;
```

Record the number of rows.

In the demonstration, the source initially contained:

```text
153 rows
```

Later additional records were inserted and the table contained:

```text
233 rows
```

This gives us data that can be used to validate replication.

---

# 8. Step 2 – Enable Disaster Recovery

Open:

```text
Azure Portal
    ↓
Virtual Machines
    ↓
SQL VM
    ↓
Disaster recovery
```

Choose the target region:

```text
West Europe
```

The purpose is:

```text
North Europe
       |
       | ASR
       v
West Europe
```

The instructor's configuration is designed so that if the source application in North Europe becomes unavailable, the infrastructure can be brought up in West Europe.

---

# 9. Step 3 – Configure Advanced Settings

Proceed to the advanced settings.

The ASR configuration creates/configures recovery infrastructure in the target region.

The demonstration creates:

```text
Target Resource Group
        |
        +-- Target VNet
        |
        +-- Replicated OS disk
        |
        +-- Replicated Data disks
```

The target resource group is created in the West Europe region.

---

# 10. Step 4 – Storage and Cache

The Site Recovery configuration creates an Azure Storage Account.

Conceptually:

```text
Source VM
    |
    | Changes
    v
Cache Storage Account
    |
    | Replication
    v
Target / Recovery infrastructure
```

The storage account is used for caching replicated changes.

The practical also demonstrates replication of:

```text
OS Disk
Data Disk(s)
```

The instructor specifically verifies that both the OS-level disk and Data Disks are replicated.

---

# 11. Step 5 – Configure Replication

Review the configuration.

Then select:

```text
Start Replication
```

The process performs several operations:

```text
1. Create resource group
        ↓
2. Create storage account
        ↓
3. Create target VNet
        ↓
4. Start initial replication
        ↓
5. Continue replicating changes
```

Initial replication can take time.

In the demonstration, the instructor waited approximately one hour before checking the replication health.

---

# 12. Step 6 – Verify Replication Health

Go to:

```text
Recovery Services Vault
    ↓
Replicated items
    ↓
SQL VM
```

Check:

```text
Replication health
Recovery point
RPO
```

Expected:

```text
Replication health = Healthy
```

The practical eventually showed:

```text
RPO ≈ 1 minute
```

This demonstrates that the source VM is being continuously replicated.

---

# 13. Important – ASR Does NOT Immediately Create the Target VM

This is one of the most important observations from the practical.

After replication is enabled:

```text
Source VM
     |
     v
Replicated disks / recovery data
```

There is **not necessarily a running target Azure VM yet**.

The instructor verifies that:

```text
Target resource group       YES
Target VNet                 YES
Replicated disks            YES
Target Azure VM             NO
```

The target VM is created when a failover is performed.

Remember:

```text
Replication
     ≠
Running duplicate VM
```

Instead:

```text
Replication
     ↓
Recovery point
     ↓
Failover
     ↓
Target VM created
```

---

# 14. Step 7 – Generate New SQL Data

To prove that replication is actually carrying current data, connect to the source SQL VM.

Run:

```sql
SELECT *
FROM log_data;
```

The practical initially showed:

```text
153 rows
```

Additional records were then inserted.

The table eventually showed:

```text
233 rows
```

This gives us a clear test condition:

```text
Source database
      |
      +-- 233 rows
```

We can later verify whether the failover VM also contains those rows.

---

# 15. Step 8 – Wait for the Latest Recovery Point

Return to:

```text
Recovery Services Vault
    ↓
Replicated Items
    ↓
SQL VM
```

Refresh the recovery point.

Initially the recovery point may still be older than the latest source data.

For example:

```text
Current source data:
233 rows

Latest RPO:
11:01
```

Wait for replication to catch up.

After some time:

```text
Latest RPO:
11:11
```

The latest recovery point should now contain the newly added records.

---

# 16. Step 9 – Test Failover

Do not immediately perform production failover just to test the configuration.

Use:

```text
Test Failover
```

This allows us to validate the recovery process without treating the test as an actual disaster recovery event.

Navigate to:

```text
Recovery Services Vault
    ↓
Replicated Items
    ↓
SQL VM
    ↓
Test Failover
```

Choose the appropriate recovery point.

Select the target Azure virtual network.

Then start:

```text
Test Failover
```

The demonstration uses the automatically configured Azure virtual network for the test failover.

---

# 17. Step 10 – Monitor the Site Recovery Job

Go to:

```text
Recovery Services Vault
    ↓
Site Recovery Jobs
```

You should see:

```text
Test Failover
      |
      +-- In Progress
      |
      +-- Creating VM
      |
      +-- Preparing VM
      |
      +-- Completed
```

The practical shows the VM creation and preparation steps completing before the recovered VM becomes available.

---

# 18. Step 11 – Verify the Test VM

Go to:

```text
Virtual Machines
```

You should now see:

```text
SQL VM
SQL VM Test
```

The important point is that:

```text
SQL VM Test
```

was created as a result of the test failover.

The instructor specifically observes the new VM after the test failover.

---

# 19. Step 12 – Understand Networking After Failover

Inspect:

```text
SQL VM Test
    ↓
Networking
```

In the demonstration, the recovered VM did **not** automatically have:

```text
Public IP
NSG
```

The instructor therefore manually creates these resources for the test environment.

This is an important operational consideration.

Your DR design should consider:

```text
VM
VNet
Subnet
NSG
Public IP
Load Balancer
DNS
Application configuration
Database connectivity
Security rules
```

Do not assume that a recovered VM automatically recreates every surrounding networking component exactly as required by your application.

---

# 20. Step 13 – Create Public IP

Create:

```text
Public IP
```

Configuration:

```text
Resource Group : ASR target resource group
Region         : West Europe
SKU            : Standard
```

Create the resource.

Then associate it with the network interface of:

```text
SQL VM Test
```

The instructor associates the created public IP through the VM's network interface/IP configuration.

---

# 21. Step 14 – Create Network Security Group

Create:

```text
Network Security Group
```

Use:

```text
Resource Group : ASR target resource group
Region         : West Europe
```

Then create an inbound rule allowing SQL Server traffic.

Example:

```text
Protocol : TCP
Port     : 1433
Service  : MS SQL
```

Then associate the NSG with the network interface of:

```text
SQL VM Test
```

The demonstration specifically adds an MS SQL inbound rule for port **1433**.

> For a production environment, avoid exposing SQL Server directly to the public Internet unless there is a strong security requirement. Prefer private networking, VPN/ExpressRoute, controlled source IPs, and appropriate security controls.

---

# 22. Step 15 – Connect to the Recovered SQL VM

Obtain the public IP address assigned to:

```text
SQL VM Test
```

Open:

```text
SQL Server Management Studio
```

Connect to the recovered SQL Server.

Then verify:

```text
Databases
    ↓
appdb
```

Open a new query and execute:

```sql
SELECT *
FROM log_data;
```

Expected result:

```text
233 rows
```

The practical confirms that the recovered VM contains the `appdb` database and the `log data` table with 233 rows.

---

# 23. What Did We Prove?

The test demonstrates:

```text
SOURCE
North Europe
     |
     | Continuous replication
     v
Recovery infrastructure
     |
     | Test Failover
     v
TARGET
West Europe
     |
     v
SQL VM Test
     |
     v
appdb
     |
     v
233 rows
```

The source and recovered database contain the same demonstrated data because the data was replicated continuously.

---

# 24. Step 16 – Cleanup Test Failover

After testing, do not leave the test environment running.

Go to:

```text
SQL VM
    ↓
Disaster Recovery
    ↓
Cleanup Test Failover
```

Confirm the cleanup.

The test failover environment is then removed.

Verify:

```text
Virtual Machines
```

You should again see only:

```text
SQL VM
```

and not:

```text
SQL VM Test
```

---

# 25. Step 17 – Delete Manually Created Test Resources

Because the public IP and NSG were created manually for the test, remove them manually.

Delete:

```text
Test Public IP
Test NSG
```

This prevents unnecessary Azure charges and avoids leaving temporary resources behind.

---

# 26. Step 18 – Disable Replication

Return to:

```text
SQL VM
    ↓
Disaster Recovery
```

Choose:

```text
Disable Replication
```

Provide the reason, for example:

```text
Testing completed
```

Confirm the operation.

The replicated item will eventually be removed from the Recovery Services Vault.

---

# 27. Step 19 – Verify Replication Is Disabled

Wait for the operation to complete.

Return to:

```text
SQL VM
    ↓
Disaster Recovery
```

You should now see the option to:

```text
Start replication
```

rather than the active replication configuration.

Then go to:

```text
Recovery Services Vault
    ↓
Replicated Items
```

Expected:

```text
No replicated items
```

The demonstration confirms that the replicated item disappears after replication is disabled.

---

# 28. Step 20 – Delete the Recovery Services Vault

Only delete the Recovery Services Vault after confirming:

```text
Replication disabled
        ↓
No replicated items
        ↓
Test failover cleaned
        ↓
Temporary resources deleted
        ↓
Vault can be deleted
```

The practical explicitly notes that replication should be disabled before deleting the Recovery Services Vault.

---

# 29. Complete Practical Flow

```text
Existing SQL VM
      |
      v
Enable Disaster Recovery
      |
      v
Select Target Region
      |
      v
Configure Recovery Services Vault
      |
      v
Configure Target VNet
      |
      v
Configure Storage / Cache
      |
      v
Start Replication
      |
      v
Initial Replication
      |
      v
Replication Health = Healthy
      |
      v
Monitor RPO
      |
      v
Generate New SQL Data
      |
      v
Wait for Latest Recovery Point
      |
      v
TEST FAILOVER
      |
      v
Create SQL VM Test
      |
      v
Configure Required Networking
      |
      v
Connect using SSMS
      |
      v
Verify appdb
      |
      v
Verify 233 Rows
      |
      v
Cleanup Test Failover
      |
      v
Disable Replication
      |
      v
Delete Temporary Resources
      |
      v
Delete Recovery Services Vault
```

---

# 30. Key Teaching Points

## Point 1 – Backup vs ASR

```text
Backup
   ↓
Point-in-time backup
   ↓
Restore

ASR
   ↓
Continuous replication
   ↓
Recovery point
   ↓
Failover
```

---

## Point 2 – RPO

RPO tells us how far behind the recovery point is from the source.

Example:

```text
RPO = 1 minute
```

means the recovery point is approximately one minute behind the source at that observation.

---

## Point 3 – Replication Does Not Mean Running VM

Before failover:

```text
Target VM = NOT necessarily running
```

The replicated disks/recovery information exist so that a VM can be created during failover.

---

## Point 4 – Test Failover Is Important

A DR configuration should not merely exist.

You should periodically prove:

```text
Replication works
       +
Failover works
       +
Application starts
       +
Database works
       +
Networking works
```

The practical specifically uses **Test Failover** to validate the recovery process.

---

## Point 5 – Application DR Is Bigger Than VM DR

Recovering the VM is only one part of disaster recovery.

Think:

```text
VM
 |
 +-- OS
 +-- Database
 +-- Data
 +-- Network
 +-- NSG
 +-- IP/DNS
 +-- Application
 +-- Dependencies
 +-- Authentication
 +-- Secrets
 +-- Monitoring
```

Your DR runbook should therefore test the complete application, not just whether the VM starts.

---

# 31. Interview Questions

### Q1. What is Azure Site Recovery?

Azure Site Recovery is a disaster-recovery service that replicates workloads to a recovery location and allows them to be recovered through failover.

### Q2. What is the primary purpose of ASR?

```text
Business Continuity
+
Disaster Recovery
+
Application Failover
```

### Q3. What is RPO?

Recovery Point Objective indicates the amount of recent data that could potentially be lost during recovery.

### Q4. Why is ASR different from backup?

Backup stores recovery copies, whereas ASR continuously replicates workloads so that a more recent recovery point can be used for failover.

### Q5. Does ASR immediately create a second running VM?

No. In this practical, replication creates recovery infrastructure and replicated disks; the target VM is created during failover.

### Q6. Why perform Test Failover?

To validate the DR process without performing the actual production failover.

### Q7. What should you verify after failover?

```text
VM
Network
Application
Database
Data
Connectivity
Security
DNS
```

### Q8. What should be cleaned after Test Failover?

```text
Test VM
Temporary Public IP
Temporary NSG
Other temporary resources
```

### Q9. What should be done before deleting the Recovery Services Vault?

Disable replication and verify that there are no remaining replicated items.

---

# 32. Final Takeaway

The complete concept is:

```text
                  DISASTER
                     |
                     v
             Source unavailable
                     |
                     v
              Azure Site Recovery
                     |
             Latest recovery point
                     |
                     v
                  Failover
                     |
                     v
              Target VM created
                     |
                     v
              Application starts
                     |
                     v
              Database available
                     |
                     v
             Business continues
```

**Azure Backup answers:**  
> "How do I restore my data?"

**Azure Site Recovery answers:**  
> "How do I recover my workload in another location when the primary site is unavailable?"

The practical concludes by disabling replication and confirming that the replicated item is removed from the Recovery Services Vault.
