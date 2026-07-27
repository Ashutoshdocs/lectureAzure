###########################################################
# Azure Allow Forwarded Traffic Lab
###########################################################
cls
$LOCATION = "centralindia"
$RG = "RG-AllowForwardDemo"

$USERNAME = "azureuser"
$PASSWORD = "Azure@123456789"

$IMAGE = "Ubuntu2404"

###########################################################
# Create Resource Group
###########################################################

Write-Host "Creating Resource Group..." -ForegroundColor Green

az group create `
    --name $RG `
    --location $LOCATION

###########################################################
# Create VNet A
###########################################################

Write-Host "Creating VNetA..." -ForegroundColor Green

az network vnet create `
    --resource-group $RG `
    --name VNetA `
    --address-prefix 10.1.0.0/16 `
    --subnet-name SubnetA `
    --subnet-prefix 10.1.0.0/24

###########################################################
# Create VNet B
###########################################################

Write-Host "Creating VNetB..." -ForegroundColor Green

az network vnet create `
    --resource-group $RG `
    --name VNetB `
    --address-prefix 10.2.0.0/16 `
    --subnet-name SubnetB `
    --subnet-prefix 10.2.0.0/24

###########################################################
# Create VNet C
###########################################################

Write-Host "Creating VNetC..." -ForegroundColor Green

az network vnet create `
    --resource-group $RG `
    --name VNetC `
    --address-prefix 10.3.0.0/16 `
    --subnet-name SubnetC `
    --subnet-prefix 10.3.0.0/24

###########################################################
# Create VM-A
###########################################################

Write-Host "Creating VM-A..." -ForegroundColor Green

az vm create `
    --resource-group $RG `
    --name VM-A `
    --image $IMAGE `
    --size Standard_B2s `
    --authentication-type password `
    --admin-username $USERNAME `
    --admin-password $PASSWORD `
    --vnet-name VNetA `
    --subnet SubnetA `
    --private-ip-address 10.1.0.4 `
    --public-ip-sku Standard `
    --nsg-rule SSH

###########################################################
# Create RouterVM
###########################################################

Write-Host "Creating RouterVM..." -ForegroundColor Green

az vm create `
    --resource-group $RG `
    --name RouterVM `
    --image $IMAGE `
    --size Standard_B2s `
    --authentication-type password `
    --admin-username $USERNAME `
    --admin-password $PASSWORD `
    --vnet-name VNetB `
    --subnet SubnetB `
    --private-ip-address 10.2.0.4 `
    --public-ip-sku Standard `
    --nsg-rule SSH

###########################################################
# Create VM-C
###########################################################

Write-Host "Creating VM-C..." -ForegroundColor Green

az vm create `
    --resource-group $RG `
    --name VM-C `
    --image $IMAGE `
    --size Standard_B2s `
    --authentication-type password `
    --admin-username $USERNAME `
    --admin-password $PASSWORD `
    --vnet-name VNetC `
    --subnet SubnetC `
    --private-ip-address 10.3.0.4 `
    --public-ip-sku Standard `
    --nsg-rule SSH

###########################################################
# Display Information
###########################################################

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Environment Created Successfully" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "VM Public IP Addresses" -ForegroundColor Yellow

az vm list-ip-addresses `
    --resource-group $RG `
    -o table

Write-Host ""
Write-Host "Private IPs" -ForegroundColor Yellow

Write-Host "VM-A      : 10.1.0.4"
Write-Host "RouterVM  : 10.2.0.4"
Write-Host "VM-C      : 10.3.0.4"

Write-Host ""
Write-Host "Next Steps" -ForegroundColor Yellow
Write-Host "1. Configure VNet Peering"
Write-Host "2. Enable IP Forwarding on RouterVM NIC"
Write-Host "3. Run the Linux router setup script on RouterVM"
Write-Host "4. Create User Defined Routes (UDRs)"
Write-Host "5. Test with Allow Forwarded Traffic = Disabled"
Write-Host "6. Enable Allow Forwarded Traffic"
Write-Host "7. Test again"