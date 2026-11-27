# Module 04 – Create and Manage Resource Groups

## Objective
Create, inspect, tag, list, and delete a resource group.

## 1. Set variables
```powershell
$Location = "centralindia"
$RG = "rg-azps-training"
```

## 2. Create resource group
```powershell
New-AzResourceGroup -Name $RG -Location $Location
```

## 3. Show and list
```powershell
Get-AzResourceGroup -Name $RG
Get-AzResourceGroup | Format-Table ResourceGroupName, Location, ProvisioningState
```

## 4. Add tags
```powershell
Set-AzResourceGroup -Name $RG -Tag @{Environment="Training";Owner="CloudClass"}
Get-AzResourceGroup -Name $RG | Select-Object -ExpandProperty Tags
```

## 5. Delete (destructive)
```powershell
Remove-AzResourceGroup -Name $RG -Force
```

## Teaching points
- A resource group is a management and lifecycle boundary, not a physical container.
- Resources in a resource group can be in different regions.
- Deleting a resource group deletes resources inside it.
- Use tags to classify and report on resources.

## Lab task
Create a resource group, tag it, inspect the tags, and delete it only after confirming it is a dedicated lab group.
