# Module 14 – End-to-End Azure PowerShell Infrastructure Project

## Scenario
Create a Linux web VM environment using individual Azure PowerShell cmdlets.

## Architecture
```text
Resource Group
  ├── Virtual Network (10.30.0.0/16)
  │     └── Subnet (10.30.1.0/24)
  ├── Network Security Group (SSH restricted to your IP)
  ├── Public IP
  ├── Network Interface
  └── Linux Virtual Machine
        └── Managed OS disk
```

## 1. Set variables and create resource group
```powershell
$Location = "centralindia"
$RG = "rg-azps-project"
$VNetName = "vnet-project"
$SubnetName = "snet-web"
$NsgName = "nsg-project"
$PipName = "pip-project"
$NicName = "nic-project"
$VmName = "vm-project"

New-AzResourceGroup -Name $RG -Location $Location
```

## 2. Create network
```powershell
$Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.30.1.0/24"
$VNet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG -Location $Location -AddressPrefix "10.30.0.0/16" -Subnet $Subnet
```

## 3. Create NSG and SSH rule
```powershell
$Nsg = New-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $RG -Location $Location
$Rule = New-AzNetworkSecurityRuleConfig -Name "Allow-SSH-My-IP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix "<YOUR_PUBLIC_IP>/32" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "22"
$Nsg.SecurityRules.Add($Rule)
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $Nsg
```

## 4. Associate NSG with subnet
```powershell
$VNet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG
Set-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNet -AddressPrefix "10.30.1.0/24" -NetworkSecurityGroupId $Nsg.Id
$VNet | Set-AzVirtualNetwork
```

## 5. Public IP and NIC
```powershell
$Pip = New-AzPublicIpAddress -Name $PipName -ResourceGroupName $RG -Location $Location -AllocationMethod Static -Sku Standard
$Subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork (Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG)
$Nic = New-AzNetworkInterface -Name $NicName -ResourceGroupName $RG -Location $Location -SubnetId $Subnet.Id -PublicIpAddressId $Pip.Id -NetworkSecurityGroupId $Nsg.Id
```

## 6. SSH key and VM
```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azps_project_key" -C "azps-project"
$AdminUser = "azureuser"
$PublicKey = Get-Content "$HOME\.ssh\azps_project_key.pub" -Raw
$Credential = [pscredential]::new($AdminUser, (ConvertTo-SecureString "TemporaryUnusedPassword!123" -AsPlainText -Force))
$VmConfig = New-AzVMConfig -VMName $VmName -VMSize "Standard_B1s"
$VmConfig = Set-AzVMOperatingSystem -VM $VmConfig -Linux -ComputerName $VmName -Credential $Credential -DisablePasswordAuthentication
$VmConfig = Add-AzVMSshPublicKey -VM $VmConfig -KeyData $PublicKey -Path "/home/$AdminUser/.ssh/authorized_keys"
$VmConfig = Set-AzVMSourceImage -VM $VmConfig -PublisherName "Canonical" -Offer "ubuntu-24_04-lts" -Skus "server" -Version "latest"
$VmConfig = Add-AzVMNetworkInterface -VM $VmConfig -Id $Nic.Id
New-AzVM -ResourceGroupName $RG -Location $Location -VM $VmConfig
```

## 7. Verify and connect
```powershell
Get-AzVM -ResourceGroupName $RG -Name $VmName -Status
$PublicIp = (Get-AzPublicIpAddress -Name $PipName -ResourceGroupName $RG).IpAddress
ssh -i "$HOME\.ssh\azps_project_key" "$AdminUser@$PublicIp"
```

## Assessment checklist
- [ ] Resource group created in the selected region.
- [ ] VNet and subnet use valid non-overlapping ranges.
- [ ] SSH source is restricted to the learner's public IP.
- [ ] Public IP and NIC are associated correctly.
- [ ] VM is deployed and SSH works.
- [ ] Learner can explain the purpose of every resource.

## Extension challenges
1. Add an HTTP rule and install Nginx on the VM.
2. Create and attach a 32-GB data disk.
3. Enable system-assigned managed identity.
4. Assign Reader access to the VM identity at resource-group scope.
5. Deploy in another region and compare configuration.
