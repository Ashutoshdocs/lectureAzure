$RG = "RG-AllowForwardDemo"

Write-Host "Enabling Allow Forwarded Traffic..." -ForegroundColor Green

az network vnet peering update `
    --resource-group $RG `
    --vnet-name VNetA `
    --name A-to-B `
    --set allowForwardedTraffic=true

az network vnet peering update `
    --resource-group $RG `
    --vnet-name VNetB `
    --name B-to-A `
    --set allowForwardedTraffic=true

az network vnet peering update `
    --resource-group $RG `
    --vnet-name VNetB `
    --name B-to-C `
    --set allowForwardedTraffic=true

az network vnet peering update `
    --resource-group $RG `
    --vnet-name VNetC `
    --name C-to-B `
    --set allowForwardedTraffic=true

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Allow Forwarded Traffic Enabled" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Cyan