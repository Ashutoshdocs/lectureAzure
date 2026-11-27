# Module 06 – Create a Virtual Network

## Objective
Create a VNet and understand its address space and subnet configuration.

## 1. Variables
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$VNetName = "vnet-azps"
```

## 2. Create VNet with an initial subnet
```powershell
$Subnet = New-AzVirtualNetworkSubnetConfig -Name "snet-app" -AddressPrefix "10.50.1.0/24"
$VNet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG -Location $Location -AddressPrefix "10.50.0.0/16" -Subnet $Subnet
```

## 3. Verify
```powershell
Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG | Format-List Name, Location, AddressSpace, Subnets
```

## Teaching points
- The VNet address space must not overlap with connected networks.
- Subnets divide the VNet address space.
- Plan address ranges before connecting VNets or on-premises networks.

## Lab task
Create a second VNet with a different address range and compare its properties.
