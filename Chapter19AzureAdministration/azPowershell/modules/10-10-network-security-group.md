# Module 10 – Create and Configure a Network Security Group

## Objective
Create an NSG, add a restricted SSH rule, and associate the NSG with a subnet.

## 1. Create NSG
```powershell
$RG = "rg-azps-training"
$Location = "centralindia"
$Nsg = New-AzNetworkSecurityGroup -Name "nsg-azps" -ResourceGroupName $RG -Location $Location
```

## 2. Add SSH rule restricted to your public IP
Replace the placeholder with your public IPv4 address in CIDR notation.
```powershell
$SshRule = New-AzNetworkSecurityRuleConfig -Name "Allow-SSH-My-IP" -Description "SSH from admin public IP only" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix "<YOUR_PUBLIC_IP>/32" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "22"
$Nsg.SecurityRules.Add($SshRule)
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $Nsg
```

## 3. Associate NSG with subnet
```powershell
$VNet = Get-AzVirtualNetwork -Name "vnet-azps" -ResourceGroupName $RG
Set-AzVirtualNetworkSubnetConfig -Name "snet-app" -VirtualNetwork $VNet -AddressPrefix "10.50.1.0/24" -NetworkSecurityGroupId $Nsg.Id
$VNet | Set-AzVirtualNetwork
```

## 4. Verify
```powershell
Get-AzNetworkSecurityGroup -Name "nsg-azps" -ResourceGroupName $RG | Select-Object -ExpandProperty SecurityRules
```

## Teaching points
- Lower numerical priority is evaluated first.
- NSGs support inbound and outbound rules.
- A rule allowing traffic does not override routing, firewalls, or other security controls.
- Restrict SSH; do not use `*` as a production source.

## Lab task
Add an HTTP rule on TCP 80 with priority 1010 and discuss whether the VM needs public HTTP access.
