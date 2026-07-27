# =====================================================
# Allow Forwarded Traffic Demo Setup
# =====================================================

$RG = "RG-AllowForwardDemo"

$RouterNIC = "RouterVMVMNic"

$RouterIP = "10.2.0.4"

$VNetA = "VNetA"
$SubnetA = "SubnetA"

$VNetC = "VNetC"
$SubnetC = "SubnetC"

$RouteTableA = "RT-A"
$RouteTableC = "RT-C"

Write-Host ""
Write-Host "===================================="
Write-Host "Enabling NIC IP Forwarding"
Write-Host "===================================="

az network nic update `
    --resource-group $RG `
    --name $RouterNIC `
    --ip-forwarding true

Write-Host ""
Write-Host "===================================="
Write-Host "Creating Route Table RT-A"
Write-Host "===================================="

az network route-table create `
    -g $RG `
    -n $RouteTableA

az network route-table route create `
    -g $RG `
    --route-table-name $RouteTableA `
    -n ToVNetC `
    --address-prefix 10.3.0.0/16 `
    --next-hop-type VirtualAppliance `
    --next-hop-ip-address $RouterIP

az network vnet subnet update `
    -g $RG `
    --vnet-name $VNetA `
    -n $SubnetA `
    --route-table $RouteTableA

Write-Host ""
Write-Host "===================================="
Write-Host "Creating Route Table RT-C"
Write-Host "===================================="

az network route-table create `
    -g $RG `
    -n $RouteTableC

az network route-table route create `
    -g $RG `
    --route-table-name $RouteTableC `
    -n ToVNetA `
    --address-prefix 10.1.0.0/16 `
    --next-hop-type VirtualAppliance `
    --next-hop-ip-address $RouterIP

az network vnet subnet update `
    -g $RG `
    --vnet-name $VNetC `
    -n $SubnetC `
    --route-table $RouteTableC

Write-Host ""
Write-Host "===================================="
Write-Host "Verification"
Write-Host "===================================="

Write-Host ""
Write-Host "NIC IP Forwarding"

az network nic show `
    -g $RG `
    -n $RouterNIC `
    --query "enableIPForwarding"

Write-Host ""
Write-Host "Route Table A"

az network route-table route list `
    -g $RG `
    --route-table-name $RouteTableA `
    -o table

Write-Host ""
Write-Host "Route Table C"

az network route-table route list `
    -g $RG `
    --route-table-name $RouteTableC `
    -o table

Write-Host ""
Write-Host "Setup Complete"