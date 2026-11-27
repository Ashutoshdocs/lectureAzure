# Azure PowerShell – Complete Teaching & Practical Lab Course

A module-wise Azure PowerShell course designed to parallel the supplied Azure CLI course. The labs use the **Az PowerShell module** and PowerShell cmdlets, not `az` commands.

## Learning outcomes

Learners will be able to:
- Install/update Az PowerShell and authenticate to Azure.
- Select subscriptions and use PowerShell cmdlets, objects, pipelines, filters and exports.
- Create/manage resource groups, Storage Accounts, VNets, subnets, public IPs, NICs, NSGs, Linux VMs, managed disks and Web Apps.
- Build a small Azure environment end to end and clean it up safely.

## Course map

| Module | Practical |
|---|---|
| 01 | Install Azure PowerShell |
| 02 | Authentication and subscriptions |
| 03 | PowerShell fundamentals, help, objects and pipelines |
| 04 | Resource groups |
| 05 | Storage Account and Blob container |
| 06 | Virtual Network |
| 07 | Subnets |
| 08 | Public IP |
| 09 | Network Interface |
| 10 | Network Security Group |
| 11 | Linux Virtual Machine |
| 12 | Managed Data Disks |
| 13 | Azure Web App |
| 14 | End-to-end infrastructure project |
| 15 | Inventory and cleanup |

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7; PowerShell 7 is recommended.
- Azure subscription and permissions to create resources.
- Internet access and an SSH client for the Linux VM practical.
- Az PowerShell installed and an authenticated session.
- For Linux VM deployment, generate an SSH key and allow SSH only from your trusted public IP.

## Suggested classroom sequence

- Session 1: Modules 01–03.
- Session 2: Modules 04–07.
- Session 3: Modules 08–10.
- Session 4: Modules 11–12.
- Session 5: Modules 13–15.

## How to use the files

1. Read this README.
2. Open the module files in numerical order.
3. Run PowerShell code in PowerShell, not Bash.
4. Replace placeholders such as `<YOUR_PUBLIC_IP>` and `<TENANT_ID>`.
5. Run verification commands after each deployment.
6. Use a dedicated lab resource group and complete cleanup.

## Common lab variables

Dot-source the shared variables file:

```powershell
. .\templates\lab-variables.ps1
```

It defines the resource group, location, VNet, subnet, NSG, public IP, NIC, VM, Storage Account, App Service plan, and Web App names.

## PowerShell command pattern

Azure PowerShell cmdlets commonly follow this naming convention:

- `New-Az*` – create a resource.
- `Get-Az*` – retrieve resources.
- `Set-Az*` – update/configure resources.
- `Update-Az*` – apply updates to an existing resource object.
- `Remove-Az*` – delete a resource.

Use `Get-Help <Cmdlet> -Examples` and `Get-Command *<keyword>*` to explore.

## Important safety rules

- Do not hard-code passwords, client secrets, private keys or tokens.
- Prefer managed identity or workload identity federation for automation.
- Grant least-privilege RBAC at the narrowest practical scope.
- Restrict SSH ingress to a trusted IP range; do not use `*` in production.
- VM disks, public IPs, and Storage Accounts may continue to incur charges.
- `Remove-AzResourceGroup` is destructive. Confirm the exact resource group first.

## Notes

- Some cmdlet parameters vary across Az module versions. Use `Get-Help <Cmdlet> -Full` in the installed version.
- VM sizes, image offers, App Service runtimes, quota and regional capacity can vary by subscription and region.
- The Linux VM examples use SSH public-key authentication. The configuration cmdlet also requires a credential object in some Az.Compute versions even when password authentication is disabled; the sample uses a temporary placeholder value and does not enable password authentication. Review the installed cmdlet help before class deployment.

## Official Microsoft references

- Install Azure PowerShell: https://learn.microsoft.com/powershell/azure/install-azure-powershell
- Authenticate with Azure PowerShell: https://learn.microsoft.com/powershell/azure/authenticate-azureps
- Azure PowerShell documentation: https://learn.microsoft.com/powershell/azure/
- Az module reference: https://learn.microsoft.com/powershell/module/az/
