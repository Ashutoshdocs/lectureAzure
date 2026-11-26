<#
.SYNOPSIS
    Attach CPU-based autoscale rules to the VM Scale Set.

.DESCRIPTION
    Creates an autoscale setting that scales OUT by 1 instance when average
    CPU stays above 30% for 5 minutes, and scales IN by 1 when average CPU
    drops below 15% for 5 minutes. Requires the Azure CLI and an existing
    deployment (run deploy.ps1 first).

.EXAMPLE
    ./autoscale.ps1
    ./autoscale.ps1 -ResourceGroup my-rg -VmssName vmssdemo-vmss -Max 15
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'vmss-demo-rg',
    [string]$VmssName      = 'vmssdemo-vmss',
    [int]$Min              = 1,
    [int]$Max              = 4,
    [int]$Default          = 1,
    [int]$ScaleOutCpu      = 30,
    [int]$ScaleInCpu       = 15
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') not found. Install it from https://aka.ms/azcli."
}

$autoscaleName = "$VmssName-autoscale"

Write-Host "Creating autoscale profile '$autoscaleName'..." -ForegroundColor Cyan
az monitor autoscale create `
    --resource-group $ResourceGroup `
    --resource $VmssName `
    --resource-type Microsoft.Compute/virtualMachineScaleSets `
    --name $autoscaleName `
    --min-count $Min `
    --max-count $Max `
    --count $Default `
    --output none

Write-Host "Adding scale-OUT rule: CPU > $ScaleOutCpu% for 5m  ->  +1 instance" -ForegroundColor Cyan
az monitor autoscale rule create `
    --resource-group $ResourceGroup `
    --autoscale-name $autoscaleName `
    --condition "Percentage CPU > $ScaleOutCpu avg 5m" `
    --scale out 1 `
    --cooldown 5 `
    --output none

Write-Host "Adding scale-IN rule:  CPU < $ScaleInCpu% for 5m  ->  -1 instance" -ForegroundColor Cyan
az monitor autoscale rule create `
    --resource-group $ResourceGroup `
    --autoscale-name $autoscaleName `
    --condition "Percentage CPU < $ScaleInCpu avg 5m" `
    --scale in 1 `
    --cooldown 5 `
    --output none

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " Autoscale configured on $VmssName" -ForegroundColor Green
Write-Host " Range     : $Min - $Max instances (default $Default)"
Write-Host " Scale out : CPU > $ScaleOutCpu%"
Write-Host " Scale in  : CPU < $ScaleInCpu%"
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tip: SSH into an instance (via the LB NAT ports 50000+) and run stress.sh to trigger a scale-out." -ForegroundColor Yellow
