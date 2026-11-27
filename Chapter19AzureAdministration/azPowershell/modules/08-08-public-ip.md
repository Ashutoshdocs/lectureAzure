# Module 08 – Create and Manage a Public IP Address

## Objective
Create a Standard static public IP and inspect its allocation and DNS settings.

## 1. Create
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$PipName = "pip-azps-vm"
$Pip = New-AzPublicIpAddress -Name $PipName -ResourceGroupName $RG -Location $Location -AllocationMethod Static -Sku Standard
```

## 2. Inspect
```powershell
Get-AzPublicIpAddress -Name $PipName -ResourceGroupName $RG | Format-List Name, IpAddress, PublicIpAllocationMethod, Sku, ProvisioningState
```

## 3. Optional DNS label
DNS labels must be unique within Azure's public DNS namespace.
```powershell
Set-AzPublicIpAddress -PublicIpAddress $Pip -DomainNameLabel "unique-lab-dns-label"
```

## Teaching points
- Standard public IPs are static.
- A public IP is a billable resource.
- Public IP association alone does not make a service reachable; NSG and routing rules also matter.

## Lab task
Create a second public IP and compare its SKU and allocation method.
