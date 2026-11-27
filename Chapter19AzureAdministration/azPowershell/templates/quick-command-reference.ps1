# Azure PowerShell quick command reference

## Login / context
Connect-AzAccount
Get-AzContext
Get-AzSubscription
Set-AzContext -Subscription "<SUBSCRIPTION_ID>"

## Resource groups
New-AzResourceGroup -Name $RG -Location $Location
Get-AzResourceGroup
Remove-AzResourceGroup -Name $RG -Force

## Storage
New-AzStorageAccount -ResourceGroupName $RG -Name $Storage -Location $Location -SkuName Standard_LRS -Kind StorageV2
$ctx = New-AzStorageContext -StorageAccountName $Storage -UseConnectedAccount
New-AzStorageContainer -Name "data" -Context $ctx -Permission Off

## Networking
New-AzVirtualNetworkSubnetConfig
New-AzVirtualNetwork
New-AzPublicIpAddress
New-AzNetworkInterface
New-AzNetworkSecurityGroup
New-AzNetworkSecurityRuleConfig

## Compute
New-AzVMConfig
Set-AzVMOperatingSystem
Add-AzVMSshPublicKey
Set-AzVMSourceImage
Add-AzVMNetworkInterface
New-AzVM
Get-AzVM
Start-AzVM
Stop-AzVM
Restart-AzVM

## Managed disks
New-AzDiskConfig
New-AzDisk
Add-AzVMDataDisk
Remove-AzVMDataDisk
Update-AzVM

## Web App
New-AzAppServicePlan
New-AzWebApp
Get-AzWebApp
Set-AzWebApp

## Help
Get-Help <CMDLET> -Examples
Get-Command *<KEYWORD>*
