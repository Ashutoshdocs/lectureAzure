# Module 09 – Create a Network Interface (NIC)

## Objective
Create a NIC and connect it to an existing subnet and public IP.

## 1. Get dependencies
```powershell
$RG = "rg-azps-training"
$VNet = Get-AzVirtualNetwork -Name "vnet-azps" -ResourceGroupName $RG
$Subnet = Get-AzVirtualNetworkSubnetConfig -Name "snet-app" -VirtualNetwork $VNet
$Pip = Get-AzPublicIpAddress -Name "pip-azps-vm" -ResourceGroupName $RG
```

## 2. Create NIC
```powershell
$Nic = New-AzNetworkInterface -Name "nic-azps-vm" -ResourceGroupName $RG -Location "centralindia" -SubnetId $Subnet.Id -PublicIpAddressId $Pip.Id
```

## 3. Verify
```powershell
Get-AzNetworkInterface -Name "nic-azps-vm" -ResourceGroupName $RG | Format-List Name, IpConfigurations, NetworkSecurityGroup
```

## Teaching points
- NIC connects a VM to a virtual network.
- The NIC IP configuration references a subnet and optionally a public IP.
- NSGs can be associated with a NIC or subnet.

## Lab task
Create a second NIC with a different name and explain why it must use a subnet ID.
