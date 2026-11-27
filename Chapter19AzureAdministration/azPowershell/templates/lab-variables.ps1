# Dot-source this file from the course root:
# . .\templates\lab-variables.ps1

$Location = "centralindia"
$RG = "rg-azps-training"
$VNet = "vnet-azps"
$Subnet = "snet-app"
$NSG = "nsg-azps"
$PIP = "pip-azps-vm"
$NIC = "nic-azps-vm"
$VM = "vm-azps-linux"
$Storage = "stazps$((New-Guid).ToString('N').Substring(0,8))"
$Plan = "plan-azps-demo"
$WebApp = "webazps$((New-Guid).ToString('N').Substring(0,8))"
