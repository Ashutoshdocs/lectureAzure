# ===============================================
# Azure VNet Peering Demo
# Allow Forwarded Traffic = No
# ===============================================

$RG = "RG-AllowForwardDemo"

Write-Host "Creating VNet Peerings..." -ForegroundColor Green

#------------------------------------------------
# VNetA -> VNetB
#------------------------------------------------

az network vnet peering create `
    --resource-group $RG `
    --vnet-name VNetA `
    --name A-to-B `
    --remote-vnet VNetB `
    --allow-vnet-access true `
    --allow-forwarded-traffic false `
    --allow-gateway-transit false `
    --use-remote-gateways false

#------------------------------------------------
# VNetB -> VNetA
#------------------------------------------------

az network vnet peering create `
    --resource-group $RG `
    --vnet-name VNetB `
    --name B-to-A `
    --remote-vnet VNetA `
    --allow-vnet-access true `
    --allow-forwarded-traffic false `
    --allow-gateway-transit false `
    --use-remote-gateways false

#------------------------------------------------
# VNetB -> VNetC
#------------------------------------------------

az network vnet peering create `
    --resource-group $RG `
    --vnet-name VNetB `
    --name B-to-C `
    --remote-vnet VNetC `
    --allow-vnet-access true `
    --allow-forwarded-traffic false `
    --allow-gateway-transit false `
    --use-remote-gateways false

#------------------------------------------------
# VNetC -> VNetB
#------------------------------------------------

az network vnet peering create `
    --resource-group $RG `
    --vnet-name VNetC `
    --name C-to-B `
    --remote-vnet VNetB `
    --allow-vnet-access true `
    --allow-forwarded-traffic false `
    --allow-gateway-transit false `
    --use-remote-gateways false

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "VNet Peerings Created Successfully" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "VNetA Peerings"
az network vnet peering list `
    --resource-group $RG `
    --vnet-name VNetA `
    -o table

Write-Host ""
Write-Host "VNetB Peerings"
az network vnet peering list `
    --resource-group $RG `
    --vnet-name VNetB `
    -o table

Write-Host ""
Write-Host "VNetC Peerings"
az network vnet peering list `
    --resource-group $RG `
    --vnet-name VNetC `
    -o table