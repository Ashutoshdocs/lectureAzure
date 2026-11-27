# Module 15 – Verify and Clean Up Azure PowerShell Lab Resources

## Objective
Inventory resources, confirm the target, and delete the dedicated lab resource group.

## 1. List resource groups
```powershell
Get-AzResourceGroup | Format-Table ResourceGroupName, Location
```

## 2. List resources in the lab group
```powershell
Get-AzResource -ResourceGroupName "rg-azps-training" | Format-Table Name, ResourceType, Location
```

## 3. Export inventory before deletion
```powershell
Get-AzResource -ResourceGroupName "rg-azps-training" |
    Select-Object Name, ResourceType, Location, ResourceId |
    Export-Csv ".\lab-resource-inventory.csv" -NoTypeInformation
```

## 4. Confirm exact target
```powershell
Get-AzResourceGroup -Name "rg-azps-training" | Format-List *
```

## 5. Delete only a dedicated lab resource group
```powershell
Remove-AzResourceGroup -Name "rg-azps-training" -Force
```

## 6. Verify deletion
```powershell
Get-AzResourceGroup -Name "rg-azps-training" -ErrorAction SilentlyContinue
```

## Important
- Do not run cleanup against a production resource group.
- Resource group deletion removes all resources in that group.
- Resources created in another resource group may remain and need separate cleanup.
- Export inventory before deletion if you need a record of the lab.

## Lab task
Export a resource inventory, review it, and delete only the dedicated lab resource group.
