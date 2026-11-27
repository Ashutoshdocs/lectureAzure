# Module 11 – Create and Manage an Azure Linux Virtual Machine

## Objective
Create a Linux VM using an existing NIC and SSH public key, connect, inspect, and manage power state.

Prerequisites: resource group, VNet, subnet, NSG rule, public IP, and NIC from earlier modules.

## 1. Create SSH key pair if needed
```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azps_training_key" -C "azps-training"
```
Keep the private key private. Supply only the `.pub` file to Azure.

## 2. Create VM configuration
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$VmName = "vm-azps-linux"
$AdminUser = "azureuser"
$SshPublicKey = Get-Content "$HOME\.ssh\azps_training_key.pub" -Raw

$VmConfig = New-AzVMConfig -VMName $VmName -VMSize "Standard_B1s"
$VmConfig = Set-AzVMOperatingSystem -VM $VmConfig -Linux -ComputerName $VmName -Credential ([pscredential]::new($AdminUser, (ConvertTo-SecureString "TemporaryUnusedPassword!123" -AsPlainText -Force))) -DisablePasswordAuthentication
$VmConfig = Add-AzVMSshPublicKey -VM $VmConfig -KeyData $SshPublicKey -Path "/home/$AdminUser/.ssh/authorized_keys"
$VmConfig = Set-AzVMSourceImage -VM $VmConfig -PublisherName "Canonical" -Offer "ubuntu-24_04-lts" -Skus "server" -Version "latest"
$VmConfig = Add-AzVMNetworkInterface -VM $VmConfig -Id (Get-AzNetworkInterface -Name "nic-azps-vm" -ResourceGroupName $RG).Id
```

The credential parameter is required by the VM configuration cmdlet even when password authentication is disabled. Use a generated, non-reused placeholder password and do not store it. Confirm the current cmdlet behaviour with `Get-Help Set-AzVMOperatingSystem -Examples` in your installed Az.Compute version.

## 3. Deploy VM
```powershell
New-AzVM -ResourceGroupName $RG -Location $Location -VM $VmConfig
```

## 4. Verify and connect
```powershell
Get-AzVM -ResourceGroupName $RG -Name $VmName -Status
$PublicIp = (Get-AzPublicIpAddress -Name "pip-azps-vm" -ResourceGroupName $RG).IpAddress
ssh -i "$HOME\.ssh\azps_training_key" "$AdminUser@$PublicIp"
```

## 5. Power operations
```powershell
Stop-AzVM -ResourceGroupName $RG -Name $VmName -Force
Stop-AzVM -ResourceGroupName $RG -Name $VmName -Force -StayProvisioned
Start-AzVM -ResourceGroupName $RG -Name $VmName
Restart-AzVM -ResourceGroupName $RG -Name $VmName
```

`Stop-AzVM` without `-StayProvisioned` deallocates the VM. Disks and networking may continue to incur charges.

## 6. Resize
```powershell
Get-AzVMSize -Location $Location | Where-Object Name -eq "Standard_B2s"
$Vm = Get-AzVM -ResourceGroupName $RG -Name $VmName
$Vm.HardwareProfile.VmSize = "Standard_B2s"
Update-AzVM -ResourceGroupName $RG -VM $Vm
```

## Teaching points
- A VM references a NIC; network resources are separate Azure resources.
- SSH public key is installed on the VM; private key remains with the administrator.
- Stop/deallocate and stop-but-stay-provisioned have different billing implications.
- Check regional quota and VM-size availability before deployment.

## Lab task
Connect to the VM, run `hostname`, `ip address`, and `lsb_release -a`, then deallocate it.
