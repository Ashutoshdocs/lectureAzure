# Module 03 – Azure PowerShell Fundamentals

## Objective
Learn cmdlet discovery, help, variables, object output, filtering, and exporting results.

## 1. Discover cmdlets
```powershell
Get-Command -Module Az.Compute
Get-Command *AzStorageAccount*
```

## 2. Read help
```powershell
Get-Help Get-AzVM
Get-Help Get-AzVM -Examples
Update-Help
```

## 3. Variables
```powershell
$Location = "centralindia"
$ResourceGroupName = "rg-azps-training"
$VmName = "vm-azps-linux"
```

## 4. Object output and properties
```powershell
Get-AzResourceGroup
Get-AzResourceGroup | Format-Table ResourceGroupName, Location
Get-AzResourceGroup | Select-Object ResourceGroupName, Location, ProvisioningState
```

## 5. Filter and sort
```powershell
Get-AzResourceGroup | Where-Object Location -eq "centralindia"
Get-AzResourceGroup | Sort-Object ResourceGroupName
```

## 6. Export output
```powershell
Get-AzResourceGroup | Export-Csv .\resource-groups.csv -NoTypeInformation
Get-AzResourceGroup | ConvertTo-Json -Depth 10 | Set-Content .\resource-groups.json
```

## 7. Error handling
```powershell
try {
    Get-AzResourceGroup -Name "rg-does-not-exist" -ErrorAction Stop
}
catch {
    Write-Host "Command failed: $($_.Exception.Message)" -ForegroundColor Red
}
```

## Teaching points
- Azure PowerShell returns .NET objects, not only formatted text.
- `Select-Object` chooses properties; `Where-Object` filters objects.
- `Format-Table` is for display, not for data processing or export.
- Use `-ErrorAction Stop` when you need terminating-error handling in `try/catch`.

## Lab task
List all resource groups in a table, filter by region, and export the result to CSV.
