# Module 07 – Add and Manage Subnets

## Objective
Add a subnet to an existing VNet and inspect its configuration.

## 1. Get existing VNet
```powershell
$RG = "rg-azps-training"
$VNetName = "vnet-azps"
$VNet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG
```

## 2. Add subnet
```powershell
Add-AzVirtualNetworkSubnetConfig -Name "snet-db" -AddressPrefix "10.50.2.0/24" -VirtualNetwork $VNet
$VNet | Set-AzVirtualNetwork
```

## 3. Verify
```powershell
(Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RG).Subnets | Format-Table Name, AddressPrefix, ProvisioningState
```

## Teaching points
- A subnet prefix must fit inside the VNet address space.
- Subnet ranges must not overlap each other.
- Network security groups and route tables can be associated with subnets.

## Lab task
Add `snet-web` with a valid non-overlapping prefix and verify all subnets.
