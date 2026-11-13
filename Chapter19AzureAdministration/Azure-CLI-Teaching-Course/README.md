# Azure CLI – Complete Teaching & Practical Lab Course

A module-wise Azure CLI course for classroom teaching and hands-on practice. The labs use **Azure CLI (`az`)** from Windows PowerShell and Linux Bash (Ubuntu 22.04/24.04 compatible).

> **Teaching approach:** Explain the Azure resource, demonstrate the command, ask learners to predict the result, execute it, verify it, and discuss cleanup.

## Learning outcomes

By the end, learners should be able to:
- Install and update Azure CLI on Windows and Linux.
- Authenticate using a user account, service principal, and managed identity.
- Select subscriptions and use CLI help, output formats, JMESPath queries, and variables.
- Create and manage resource groups, storage accounts, VNets, subnets, public IPs, NICs, NSGs, VMs, disks, and Web Apps.
- Build and clean up a small Azure environment from the command line.

## Course map

| Module | File | Practical |
|---|---|---|
| 01 | `modules/01-install-azure-cli.md` | Install on Windows and Ubuntu Linux |
| 02 | `modules/02-authentication.md` | User, service principal, managed identity |
| 03 | `modules/03-cli-fundamentals.md` | Help, output, query, variables |
| 04 | `modules/04-resource-groups.md` | Resource group lifecycle |
| 05 | `modules/05-storage-account.md` | Storage account and blob container |
| 06 | `modules/06-virtual-network.md` | VNet and address space |
| 07 | `modules/07-subnets.md` | Subnet creation and inspection |
| 08 | `modules/08-public-ip.md` | Public IP creation |
| 09 | `modules/09-network-interface.md` | NIC creation and IP configuration |
| 10 | `modules/10-network-security-group.md` | NSG and security rules |
| 11 | `modules/11-virtual-machine.md` | Linux VM deployment and operations |
| 12 | `modules/12-managed-disks.md` | Data disk creation and attachment |
| 13 | `modules/13-web-app.md` | App Service plan and Web App |
| 14 | `modules/14-end-to-end-project.md` | Build a small environment end to end |
| 15 | `modules/15-cleanup.md` | Verify and delete lab resources |

## Prerequisites

1. An Azure subscription with permission to create resources.
2. A Windows computer with PowerShell 7 or Windows PowerShell, or an Ubuntu Linux VM/workstation.
3. Internet access.
4. For the VM lab, an SSH client and an SSH key pair.
5. For managed identity authentication, an Azure VM or another supported Azure host with an identity assigned and appropriate RBAC permissions.

Some resource types or VM sizes may not be available in every region or subscription. If a command fails due to quota or capacity, choose another region or size.

## Suggested classroom sequence

- **Session 1:** Modules 01–03 (installation, login, CLI fundamentals).
- **Session 2:** Modules 04–07 (resource groups, storage, VNet, subnet).
- **Session 3:** Modules 08–10 (public IP, NIC, NSG).
- **Session 4:** Modules 11–12 (VM and managed disks).
- **Session 5:** Modules 13–15 (Web App, end-to-end project, cleanup).

## How to use the files

1. Start with this README.
2. Open each module in numerical order.
3. Run the commands in the matching shell: PowerShell commands in PowerShell, Bash commands in Bash.
4. Replace every `<PLACEHOLDER>` before execution.
5. Run the verification commands after each practical.
6. Keep a record of resource names and the resource group used.

## Common lab variables

Use these values as a consistent example. Change them if the names already exist in your subscription.

**Bash**
```bash
export LOCATION="centralindia"
export RG="rg-azcli-training"
export VNET="vnet-azcli"
export SUBNET="snet-app"
export NSG="nsg-azcli"
export PIP="pip-azcli-vm"
export NIC="nic-azcli-vm"
export VM="vm-azcli-linux"
export STORAGE="stazcli$(openssl rand -hex 4)"
export PLAN="plan-azcli-demo"
export WEBAPP="webazcli$(openssl rand -hex 4)"
```

**PowerShell**
```powershell
$LOCATION = "centralindia"
$RG = "rg-azcli-training"
$VNET = "vnet-azcli"
$SUBNET = "snet-app"
$NSG = "nsg-azcli"
$PIP = "pip-azcli-vm"
$NIC = "nic-azcli-vm"
$VM = "vm-azcli-linux"
$STORAGE = "stazcli$((New-Guid).ToString('N').Substring(0,8))"
$PLAN = "plan-azcli-demo"
$WEBAPP = "webazcli$((New-Guid).ToString('N').Substring(0,8))"
```

Storage account and Web App names must be globally unique and follow Azure naming rules. Storage account names are lowercase letters and numbers, 3–24 characters. Web App names must also be globally unique.

## Important safety rules

- Do not put passwords, client secrets, private keys, or access tokens in source files, screenshots, Git repositories, or command history.
- For production automation, prefer managed identity or workload identity federation where supported. If using a service principal secret for a lab, store it securely and rotate/delete it after use.
- Grant least-privilege RBAC roles at the narrowest practical scope.
- A public IP and an open SSH rule expose a VM to the internet. Restrict SSH source IPs; do not use `*` for production.
- Stopping a VM from inside its operating system is not the same as Azure deallocation. Use `az vm deallocate` when the goal is to stop compute billing.
- Deleting a resource group deletes all resources inside it. Confirm the resource group name before cleanup.

## Official Microsoft references

- [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Authenticate to Azure CLI](https://learn.microsoft.com/cli/azure/authenticate-azure-cli)
- [Azure CLI reference](https://learn.microsoft.com/cli/azure/reference-index)
- [Create a Linux VM with Azure CLI](https://learn.microsoft.com/azure/virtual-machines/linux/quick-create-cli)
- [Azure CLI documentation](https://learn.microsoft.com/cli/azure/)
