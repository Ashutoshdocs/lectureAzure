# Module 12 – Create and Attach a Managed Data Disk

## Objective
Create a managed disk, attach it to a VM, verify it, and detach it.

Prerequisite: VM from Module 11.

## 1. Create disk configuration and disk
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$DiskConfig = New-AzDiskConfig -Location $Location -CreateOption Empty -DiskSizeGB 32 -SkuName Standard_LRS
$Disk = New-AzDisk -ResourceGroupName $RG -DiskName "disk-azps-data01" -Disk $DiskConfig
```

## 2. Attach to VM
```powershell
$Vm = Get-AzVM -ResourceGroupName $RG -Name "vm-azps-linux"
$Vm = Add-AzVMDataDisk -VM $Vm -Name "disk-azps-data01" -CreateOption Attach -ManagedDiskId $Disk.Id -Lun 0
Update-AzVM -ResourceGroupName $RG -VM $Vm
```

## 3. Verify Azure attachment
```powershell
(Get-AzVM -ResourceGroupName $RG -Name "vm-azps-linux").StorageProfile.DataDisks | Format-Table Name, Lun, DiskSizeGB, ManagedDisk
Get-AzDisk -ResourceGroupName $RG -DiskName "disk-azps-data01"
```

## 4. Verify inside Linux
```bash
lsblk
sudo fdisk -l
```

Only after positively identifying the new empty device, partition and format it. Formatting the wrong disk causes data loss.

## 5. Detach
```powershell
$Vm = Get-AzVM -ResourceGroupName $RG -Name "vm-azps-linux"
$Vm = Remove-AzVMDataDisk -VM $Vm -Name "disk-azps-data01"
Update-AzVM -ResourceGroupName $RG -VM $Vm
```

The managed disk remains as a separate resource after detaching. Delete it separately only if it is no longer required.
