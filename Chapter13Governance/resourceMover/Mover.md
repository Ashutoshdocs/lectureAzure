# 📘 Azure Resource Mover – End-to-End Practical
## AZ-104 | Move Azure Resources Across Regions

---

## 1. What is Azure Resource Mover?

Azure Resource Mover is an Azure service that helps organizations move supported Azure resources from one Azure region to another.

For example:

An organization currently hosts its application in Central India. Due to business requirements, it wants to migrate its infrastructure to South India.

Instead of manually recreating every supported resource, Azure Resource Mover helps identify dependencies and orchestrate the regional migration.

### Real-world use cases

- Move infrastructure closer to customers.
- Meet data residency requirements.
- Move workloads to a newly available Azure region.
- Support regional capacity planning.
- Respond to business requirements.
- Relocate workloads deployed in the wrong region.

## 2. What Will We Implement?

In this practical, we will:

1. Create an application infrastructure in Central India.
2. Create a Virtual Network, Subnet, NSG and VM.
3. Explore Azure Resource Mover.
4. Select the source and destination regions.
5. Add resources for migration.
6. Identify and resolve resource dependencies.
7. Prepare resources for migration.
8. Initiate the move.
9. Verify resources in South India.
10. Commit the migration.
11. Perform post-migration configuration.
12. Clean up the original resources.

---

## 3. Architecture

<text weight="semibold">Before migration</text>

```text
       Azure Subscription
               |
         Central India
               |
         RG-PROD-CI
               |
        +------+------+
        |             |
       VNet          NSG
        |
      Subnet
        |
       NIC
        |
       VM
```

<text weight="semibold">After migration</text>

```text
       Azure Subscription
               |
          South India
               |
         RG-PROD-SI
               |
        +------+------+
        |             |
       VNet          NSG
        |
      Subnet
        |
       NIC
        |
       VM
```

<text color="secondary" size="xs">Illustrative architecture. Actual migration dependencies and target resource configurations are determined during the Resource Mover workflow.</text>

---

# PART 1 – Create Source Infrastructure

## 4. Create Resource Group in Central India

Open:

https://portal.azure.com

Navigate:

```text
Resource Groups
      |
      +-- Create
```

Configure:

| Property | Value |
|---|---|
| Subscription | Your subscription |
| Resource Group | RG-PROD-CI |
| Region | Central India |

Click Review + Create, then Create.

## 5. Create Virtual Network

Navigate:

```text
Virtual Networks
      |
      +-- Create
```

Configure:

| Property | Value |
|---|---|
| Name | VNET-PROD-CI |
| Resource Group | RG-PROD-CI |
| Region | Central India |
| Address Space | 10.10.0.0/16 |
| Subnet | SUBNET-APP |
| Subnet Address | 10.10.1.0/24 |

Click Review + Create.

## 6. Create Network Security Group

Navigate:

```text
Network Security Groups
      |
      +-- Create
```

Configure:

| Property | Value |
|---|---|
| Name | NSG-PROD-CI |
| Resource Group | RG-PROD-CI |
| Region | Central India |

Create an inbound security rule for your lab access.

Example:

| Setting | Value |
|---|---|
| Source | Your public IP |
| Source port | * |
| Destination | Any |
| Destination port | 22 |
| Protocol | TCP |
| Action | Allow |
| Priority | 100 |
| Name | Allow-SSH-Lab |

Associate the NSG with SUBNET-APP.

For production, restrict SSH to approved networks or use Azure Bastion.

## 7. Create Linux Virtual Machine

Navigate:

```text
Virtual Machines
      |
      +-- Create
          |
          +-- Azure Virtual Machine
```

Configure:

### Basics

| Property | Value |
|---|---|
| VM Name | VM-PROD-CI |
| Region | Central India |
| Image | Ubuntu Server 24.04 LTS |
| Size | Standard_B2s |
| Authentication | SSH Public Key |
| Username | azureuser |

### Networking

| Property | Value |
|---|---|
| Virtual Network | VNET-PROD-CI |
| Subnet | SUBNET-APP |
| Public IP | Create new |
| NSG | NSG-PROD-CI |

Review and create the VM.

### Verify source resources

Open the resource group:

```text
RG-PROD-CI
```

You should see resources such as:

- Virtual Machine
- Network Interface
- Managed Disk
- Virtual Network
- Network Security Group
- Public IP Address

**Teaching point:** A VM is dependent on several infrastructure resources. Moving only the VM without considering its dependencies can cause networking or connectivity issues.

---

# PART 2 – Understand Resource Mover

## 8. Open Azure Resource Mover

In Azure Portal, search:

```text
Azure Resource Mover
```

Open the service.

Alternatively, use the Resource Mover documentation:

https://learn.microsoft.com/en-us/azure/resource-mover/overview

Click:

```text
Get Started
```

Then select:

```text
Move across regions
```

### Understand the source and destination

We will configure:

| Setting | Value |
|---|---|
| Source subscription | Your subscription |
| Source region | Central India |
| Destination region | South India |

Click Next.

**Important:** Azure Resource Mover supports regional moves within the same subscription. Moving across subscriptions is a separate operation performed after the regional move. <https://learn.microsoft.com/en-us/azure/resource-mover/common-questions>

---

# PART 3 – Select Resources for Migration

## 9. Select Resources to Move

On the Resources to move tab:

1. Select Select resources.
2. Choose the source resource group.
3. Select the supported resources you want to move.

For this practical, select:

- VM-PROD-CI
- VNET-PROD-CI
- NSG-PROD-CI
- Associated NIC and other required dependencies, as presented by the portal.

Review the resources.

Click Next.

## 10. Review and Add

Check:

| Setting | Expected |
|---|---|
| Source Region | Central India |
| Target Region | South India |
| Subscription | Same subscription |
| Resources | Selected source resources |

Click Proceed.

Azure Resource Mover creates a move collection and begins validating the selected resources.

Open:

```text
Azure Resource Mover
       |
       +-- Across regions
```

Your resources should appear in the move list.

---

# PART 4 – Resolve Dependencies

## 11. What Are Resource Dependencies?

A VM does not work independently.

It requires several associated resources.

Example:

```text
             Virtual Machine
                    |
                   NIC
                    |
             Virtual Network
                    |
                  Subnet
                    |
             Network Security
                    |
                   NSG
```

Other dependencies can include:

- Managed disks
- Availability sets
- Public IP addresses
- Load balancers
- Encryption-related resources

### Validate dependencies

In the Across regions view:

1. Select the resources.
2. Click Validate dependencies if shown.
3. Review the validation results.
4. If dependencies are missing, select Add dependencies.
5. Select the dependent resources.
6. Click Add dependencies.

Wait for the validation to complete.

Expected status:

```text
Prepare pending
```

**Important:** Resource Mover identifies dependencies, but not every external dependency of an application is necessarily migrated automatically. Review DNS, Key Vault, application settings, private endpoints, monitoring and other connected services separately.

---

# PART 5 – Move the Source Resource Group

## 12. Why Do We Move the Resource Group First?

For the VM migration workflow, the source resource group must be represented in the target region before preparing the VM resources.

Resource Mover generates the required resource group configuration using ARM templates.

### Prepare the resource group

1. Open Across regions.
2. Select the source resource group entry.
3. Click Prepare.
4. Review the configuration.
5. Click Prepare.

Wait for completion.

Expected status:

```text
Initiate move pending
```

### Initiate the resource group move

1. Select the resource group.
2. Click Initiate move.
3. Review the operation.
4. Click Initiate move.

Wait for completion.

Resource Mover creates the corresponding target resource group.

### Commit the resource group move

1. Select the resource group.
2. Click Commit move.
3. Confirm the operation.

Expected result:

```text
Target Resource Group:
RG-PROD-CI
Region:
South India
```

The original source resource group is still present until source cleanup.

**Teaching point:** The resource group migration is a prerequisite in the documented VM workflow. It does not mean that all resources inside the resource group have already moved.

---

# PART 6 – Configure Destination Resources

## 13. Review Target Configuration

Go to:

```text
Azure Resource Mover
       |
       +-- Across regions
```

Select the destination configuration link for the resources.

Review the target settings.

### VM configuration

Check:

| Setting | Configuration |
|---|---|
| VM Name | VM-PROD-CI |
| Destination Region | South India |
| VM Size | Standard_B2s or compatible |
| Target VNet | Target-region VNet |
| Target Subnet | Target subnet |
| OS Disk | Target disk configuration |

The target VM size must be compatible and should not be smaller than the source VM size in the documented workflow.

### Networking configuration

Review:

- Target VNet
- Target subnet
- NSG association
- NIC configuration
- Public IP configuration
- IP address allocation

**Important:** A public IP address is not retained across regions. You must configure the target public IP and update DNS records or application endpoints as needed.

---

# PART 7 – Prepare Resources for Migration

## 14. Prepare the Resources

Select the VM and its required dependent resources.

Click:

```text
Prepare
```

Review the Prepare resources pane.

Click Prepare again.

### What happens in the background?

For Azure VMs:

1. Azure Site Recovery technology is used to replicate VM data.
2. The Mobility service is installed on supported source VMs.
3. VM disks are replicated to the destination region.
4. Other supported resources are prepared using generated ARM templates.
5. Azure Resource Mover monitors preparation progress.

Wait for preparation to complete.

Expected status:

```text
Initiate move pending
```

**Important:** VM replication can take time depending on disk size, data change rate, network conditions and other factors. Monitor the operation rather than assuming it finishes immediately.

---

# PART 8 – Initiate the Move

## 15. Initiate Migration

Once preparation succeeds:

1. Open Across regions.
2. Select the VM and associated resources.
3. Confirm their status is Initiate move pending.
4. Click Initiate move.
5. Review the target configuration.
6. Confirm Initiate move.

### What happens?

For VM migration:

- The final migration operation creates the target-region VM.
- The source VM is shut down during the cutover.
- Some downtime occurs.
- Other supported resources are recreated in the destination region.

Wait for the operation to finish.

Expected status:

```text
Commit move pending
```

<text color="secondary" size="xs">Plan a maintenance window for production workloads. Test the application and validate the destination environment before committing.</text>

---

# PART 9 – Commit or Discard the Move

## 16. Understand Commit and Discard

After initiating the move, Resource Mover allows two choices.

| Operation | Purpose |
|---|---|
| Commit | Complete the regional migration |
| Discard | Discard the migration attempt and return the resources to an initiate-move-pending state |

### Option A – Discard the Move

Use this for a test where you do not want to finalize the migration.

1. Select resources in Commit move pending.
2. Click Discard move.
3. Review the operation.
4. Click Discard.

Expected status:

```text
Initiate move pending
```

You can initiate the move again.

### Option B – Commit the Move

For the actual migration:

1. Select the resources.
2. Click Commit move.
3. Review the resources.
4. Click Commit.

Wait for completion.

Expected status:

```text
Delete source pending
```

**Important:** Commit completes the target migration and stops replication. It does not automatically delete the source infrastructure.

---

# PART 10 – Verify Resources in South India

## 17. Verify the Target Resource Group

Navigate:

```text
Resource Groups
       |
       +-- RG-PROD-CI
```

Verify the region is South India.

Open the resource group.

Check that the destination resources are present.

## 18. Verify the Virtual Machine

Navigate:

```text
Virtual Machines
       |
       +-- VM-PROD-CI
```

Check:

- VM provisioning state
- VM power state
- Region
- VM size
- OS disk
- NIC
- Network configuration

## 19. Test Connectivity

Connect to the destination VM using SSH through the newly configured network path.

```bash
ssh azureuser@<TARGET_PUBLIC_IP>
```

Inside the VM:

```bash
hostname
```

```bash
ip addr
```

```bash
df -h
```

Check application availability.

If you have deployed Nginx:

```bash
sudo systemctl status nginx
```

Test the web application using its new endpoint.

**Note:** The target public IP and application endpoint may be different from the source. Update DNS, firewall rules and application configurations accordingly.

---

# PART 11 – Post-Migration Configuration

## 20. Important Items to Check

After migration, verify the following:

| Component | Required action |
|---|---|
| Public IP | Create or verify target public IP |
| DNS | Update A records or DNS labels |
| NSG | Verify inbound and outbound rules |
| Load Balancer | Recreate missing NAT rules if required |
| Monitoring | Configure target-region monitoring |
| Backup | Verify backup configuration |
| RBAC | Review role assignments |
| Managed Identity | Verify identity and application access |
| Key Vault | Verify access to secrets and certificates |
| Application | Test application functionality |

### Important Resource Mover limitations

- Public IP addresses are not retained across regions.
- DNS labels on public IP addresses need to be configured again.
- Load Balancer NAT rules are not copied automatically.
- The Azure Site Recovery Mobility service is not automatically uninstalled after the move.
- Some application dependencies need manual configuration.

---

# PART 12 – Delete Source Resources

## 21. When Should We Delete the Source?

Only delete source resources after:

1. The destination VM is working.
2. The application has been tested.
3. Network connectivity is verified.
4. DNS changes are complete.
5. Monitoring is operational.
6. The application owner has approved the migration.

### Delete Source

Navigate:

```text
Azure Resource Mover
       |
       +-- Across regions
```

Select the source resources in:

```text
Delete source pending
```

Click:

```text
Delete source
```

Review each resource before confirming.

**Warning:** This is a destructive operation. Do not delete source resources until the target environment has been fully validated and the migration has been approved.

Also review any additional temporary resources created during migration and remove them only when no longer required.

---

# PART 13 – Troubleshooting

## 22. Common Issues

| Problem | Possible solution |
|---|---|
| Resource not appearing | Verify resource type and source region |
| Dependency validation failed | Add missing dependent resources |
| Target region not available | Verify service and SKU availability |
| VM replication failed | Check Mobility service, connectivity and replication prerequisites |
| Target VM creation failed | Check VM quota and destination configuration |
| Disk replication taking too long | Check disk size and data change rate |
| Network connection failed | Check NIC, NSG, subnet and routing |
| Public IP changed | Update DNS and application endpoints |
| VM size unavailable | Select a supported SKU in South India |
| Commit failed | Review Resource Mover operation details and resolve errors |

### Check regional availability

Use:

https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/

Verify that the required VM SKU and services are available in the destination region.

---

# PART 14 – AZ-104 Important Concepts

## 23. Resource Mover vs Other Azure Services

| Service | Purpose |
|---|---|
| Azure Resource Mover | Move supported Azure resources across regions |
| Azure Site Recovery | Disaster recovery and replication |
| Azure Backup | Backup and restore |
| Azure Migrate | Assess and migrate workloads to Azure |
| Azure Resource Manager | Deploy and manage Azure resources |

### Important exam points

1. Azure Resource Mover helps move supported resources across Azure regions.
2. Resource dependencies must be validated.
3. VM migration uses replication technology.
4. Prepare is required before initiating the move.
5. Initiate move starts the regional cutover.
6. Commit finalizes the migration.
7. Discard cancels the migration attempt without finalizing it.
8. Source resource deletion is a separate operation.
9. Public IP addresses are not retained across regions.
10. Resource Mover does not automatically migrate every application dependency.

---

# PART 15 – Student Practical Assignment

## 24. Complete the Following Tasks

- [ ] Create RG-PROD-CI in Central India.
- [ ] Create VNET-PROD-CI.
- [ ] Create SUBNET-APP.
- [ ] Create NSG-PROD-CI.
- [ ] Create VM-PROD-CI.
- [ ] Open Azure Resource Mover.
- [ ] Select Central India as the source.
- [ ] Select South India as the destination.
- [ ] Add the VM and required dependencies.
- [ ] Validate dependencies.
- [ ] Prepare the source resource group.
- [ ] Initiate the resource group move.
- [ ] Commit the resource group move.
- [ ] Configure target resource settings.
- [ ] Prepare the VM and dependencies.
- [ ] Initiate the VM migration.
- [ ] Verify the target VM.
- [ ] Test application connectivity.
- [ ] Commit the migration.
- [ ] Verify target-region networking.
- [ ] Review source resources for cleanup.

---

# PART 16 – Interview Questions

## 25. Important Questions

**Q1. What is Azure Resource Mover?**

A service used to move supported Azure resources from one Azure region to another.

**Q2. What is the difference between Azure Resource Mover and Azure Site Recovery?**

Resource Mover orchestrates supported regional resource moves. Azure Site Recovery is primarily used for disaster recovery and replication. Resource Mover uses Azure Site Recovery technology for VM replication during its VM migration workflow.

**Q3. What is dependency validation?**

It identifies related resources that must be considered during the migration.

**Q4. What is the purpose of Prepare?**

It prepares the resources for migration, including replication for VMs and template generation for supported resources.

**Q5. What is the purpose of Initiate Move?**

It starts the actual regional migration and creates the target resources.

**Q6. What is the purpose of Commit?**

It finalizes the migration and stops replication.

**Q7. What is Discard Move?**

It discards the current migration attempt and allows the move to be initiated again.

**Q8. Does Azure Resource Mover automatically delete the source resources?**

No. Source cleanup is a separate step after committing the migration.

**Q9. Can we retain the same public IP when moving between regions?**

No. The target region requires a new public IP configuration.

**Q10. Can Azure Resource Mover move resources between subscriptions at the same time as the regional migration?**

No. The regional move and subscription move are separate operations.

---

# 26. Final Learning Outcome

After completing this practical, students should understand:

- Azure regional migration.
- Resource dependencies.
- Resource Mover workflow.
- Source and destination regions.
- VM replication.
- Prepare, Initiate, Commit and Discard operations.
- Target network configuration.
- Post-migration validation.
- Source resource cleanup.

## Official Microsoft Documentation

1. Azure Resource Mover overview:

https://learn.microsoft.com/en-us/azure/resource-mover/overview

2. Move Azure VMs across regions:

https://learn.microsoft.com/en-us/azure/resource-mover/tutorial-move-region-virtual-machines

3. Move resources from a resource group:

https://learn.microsoft.com/en-us/azure/resource-mover/move-region-within-resource-group

4. Azure Resource Mover FAQ:

https://learn.microsoft.com/en-us/azure/resource-mover/common-questions

5. Azure Resource relocation guidance:

https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/move-resources-overview

---

## Final AZ-104 Revision Flow

```text
Select Source Region
        |
Select Target Region
        |
Select Resources
        |
Validate Dependencies
        |
Add Missing Dependencies
        |
Prepare Resource Group
        |
Initiate Resource Group Move
        |
Commit Resource Group Move
        |
Configure Target Resources
        |
Prepare Resources
        |
Initiate Move
        |
     +--+--+
     |     |
  Discard Commit
            |
       Verify Target
            |
       Delete Source
```

**Remember:** Prepare → Initiate Move → Commit → Delete Source.

These are the key stages to understand for Azure Resource Mover.