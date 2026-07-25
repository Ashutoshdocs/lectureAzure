<#
.SYNOPSIS
    Deploy the VMSS dashboard with pure Azure CLI — no Bicep, no template.

.DESCRIPTION
    Creates the resource group, NSG, VNet, Standard Load Balancer (probe +
    HTTP rule + outbound rule), and the VM Scale Set provisioned by
    cloud-init.yaml. The outbound rule is created before the instances boot
    so cloud-init can reach the internet to install NGINX.

    Requires the Azure CLI (`az`) and an active login (`az login`).

.EXAMPLE
    ./deploy.ps1
    ./deploy.ps1 -ResourceGroup my-rg -Location eastus -InstanceCount 3
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'vmss-demo-rg',
    [string]$Location      = 'centralindia',
    [string]$Project       = 'vmssdemo',
    [string]$VmSku         = 'Standard_B1s',
    [int]$InstanceCount    = 2,
    [string]$AdminUsername = 'azureuser'
)

$ErrorActionPreference = 'Stop'

$Vnet   = "$Project-vnet"
$Subnet = 'default'
$Nsg    = "$Project-nsg"
$Pip    = "$Project-pip"
$Lb     = "$Project-lb"
$Vmss   = "$Project-vmss"
$Fe     = 'frontend'
$BePool = 'bepool'
$Probe  = 'httpProbe'

$cloudInit = Join-Path $PSScriptRoot 'cloud-init.yaml'

# --- Preflight -----------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') not found. Install from https://aka.ms/azcli, then 'az login'."
}
if (-not (az account show 2>$null)) { throw "Not signed in. Run 'az login' first." }
if (-not (Test-Path $cloudInit))    { throw "cloud-init.yaml not found next to this script." }

$securePwd = Read-Host "Enter a VM admin password (min 12 chars, mixed complexity)" -AsSecureString
$bstr  = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
if ($plain.Length -lt 12) { throw "Password must be at least 12 characters." }

Write-Host ">> Subscription: $(az account show --query name -o tsv)" -ForegroundColor Green

# --- Resource group ------------------------------------------------
Write-Host ">> Creating resource group '$ResourceGroup' ($Location)" -ForegroundColor Cyan
az group create -n $ResourceGroup -l $Location -o none

# --- NSG (HTTP 80 + SSH 22) ----------------------------------------
Write-Host ">> Creating NSG and rules" -ForegroundColor Cyan
az network nsg create -g $ResourceGroup -n $Nsg -o none
az network nsg rule create -g $ResourceGroup --nsg-name $Nsg -n Allow-HTTP `
  --priority 100 --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes '*' --destination-port-ranges 80 -o none
az network nsg rule create -g $ResourceGroup --nsg-name $Nsg -n Allow-SSH `
  --priority 110 --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes '*' --destination-port-ranges 22 -o none

# --- VNet + subnet (attach NSG) ------------------------------------
Write-Host ">> Creating VNet and subnet" -ForegroundColor Cyan
az network vnet create -g $ResourceGroup -n $Vnet `
  --address-prefixes 10.0.0.0/16 `
  --subnet-name $Subnet --subnet-prefixes 10.0.0.0/24 -o none
az network vnet subnet update -g $ResourceGroup --vnet-name $Vnet -n $Subnet `
  --network-security-group $Nsg -o none

# --- Public IP + Standard LB ---------------------------------------
Write-Host ">> Creating public IP and Standard load balancer" -ForegroundColor Cyan
az network public-ip create -g $ResourceGroup -n $Pip `
  --sku Standard --allocation-method Static -o none
az network lb create -g $ResourceGroup -n $Lb --sku Standard `
  --public-ip-address $Pip --frontend-ip-name $Fe --backend-pool-name $BePool -o none

# --- Probe + HTTP rule ---------------------------------------------
Write-Host ">> Adding probe and HTTP rule (80 -> 80)" -ForegroundColor Cyan
az network lb probe create -g $ResourceGroup --lb-name $Lb -n $Probe `
  --protocol Tcp --port 80 -o none
az network lb rule create -g $ResourceGroup --lb-name $Lb -n httpRule `
  --protocol Tcp --frontend-port 80 --backend-port 80 `
  --frontend-ip $Fe --backend-pool-name $BePool `
  --probe-name $Probe --disable-outbound-snat true -o none

# --- Outbound rule (internet for cloud-init) -----------------------
Write-Host ">> Adding outbound rule" -ForegroundColor Cyan
az network lb outbound-rule create -g $ResourceGroup --lb-name $Lb -n outbound `
  --frontend-ip-configs $Fe --address-pool $BePool --protocol All --idle-timeout 4 -o none

# --- VM Scale Set --------------------------------------------------
Write-Host ">> Creating VM Scale Set (slow part)" -ForegroundColor Cyan
az vmss create -g $ResourceGroup -n $Vmss `
  --orchestration-mode Uniform `
  --image Ubuntu2204 `
  --vm-sku $VmSku `
  --instance-count $InstanceCount `
  --admin-username $AdminUsername `
  --admin-password $plain `
  --vnet-name $Vnet --subnet $Subnet `
  --lb $Lb --backend-pool-name $BePool `
  --upgrade-policy-mode manual `
  --custom-data $cloudInit `
  --computer-name-prefix vmss -o none

$plain = $null

# --- Result --------------------------------------------------------
$ip = az network public-ip show -g $ResourceGroup -n $Pip --query ipAddress -o tsv
Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " Deployment complete!" -ForegroundColor Green
Write-Host " Public IP : $ip"
Write-Host " Dashboard : http://$ip"
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Give cloud-init ~2-3 min to install NGINX, then open the URL."
Write-Host "Next: enable autoscale ->  ./autoscale.ps1 -ResourceGroup $ResourceGroup" -ForegroundColor Yellow
