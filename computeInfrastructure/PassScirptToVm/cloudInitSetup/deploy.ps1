#=========================================================
# Azure VM Creation using Username/Password + Cloud-Init
#=========================================================

# Variables

$ResourceGroup = "CloudInit-RG"
$Location      = "CentralIndia"
$VMName        = "cloudinit-vm01"
$VMSize        = "Standard_B1s"
$Image         = "Ubuntu2404"

$Username      = "azureuser"
$Password      = "P@ssw0rd12345!"      # Change this to a strong password

$CloudInitFile = ".\cloud-init.yaml"

#---------------------------------------------------------
Write-Host ""
Write-Host "==============================================="
Write-Host "Creating Resource Group"
Write-Host "==============================================="

az group create `
    --name $ResourceGroup `
    --location $Location

#---------------------------------------------------------
Write-Host ""
Write-Host "==============================================="
Write-Host "Creating Ubuntu VM"
Write-Host "==============================================="

az vm create `
    --resource-group $ResourceGroup `
    --name $VMName `
    --image $Image `
    --size $VMSize `
    --admin-username $Username `
    --admin-password $Password `
    --authentication-type password `
    --custom-data $CloudInitFile `
    --public-ip-sku Standard

#---------------------------------------------------------
Write-Host ""
Write-Host "Opening Port 80..."

az vm open-port `
    --resource-group $ResourceGroup `
    --name $VMName `
    --port 80

#---------------------------------------------------------
Write-Host ""
Write-Host "Getting Public IP..."

$PublicIP = az vm show `
    -g $ResourceGroup `
    -n $VMName `
    -d `
    --query publicIps `
    -o tsv

#---------------------------------------------------------
Write-Host ""
Write-Host "==============================================="
Write-Host "VM Created Successfully"
Write-Host "==============================================="

Write-Host ""
Write-Host "VM Name      : $VMName"
Write-Host "ResourceGroup: $ResourceGroup"
Write-Host "Username     : $Username"
Write-Host "Password     : $Password"
Write-Host "Public IP    : $PublicIP"

Write-Host ""
Write-Host "Website:"
Write-Host "http://$PublicIP"

Write-Host ""
Write-Host "SSH:"
Write-Host "ssh $Username@$PublicIP"

Write-Host ""
Write-Host "Finished."