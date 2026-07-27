##################################################
# Azure Site-to-Site VPN Demo Lab
##################################################

$RG="VPNDemoRG"
$LOC="centralindia"

$COMPANYVNET="company-vnet"
$AZUREVNET="azure-vnet"

$COMPANYVM="companyvm"
$WEBVM="webvm"

$USER="azure"
$PASS="warrison@123"

##################################################
# Login
##################################################

az login

##################################################
# Resource Group
##################################################

az group create `
--name $RG `
--location $LOC

##################################################
# Company VNET
##################################################

az network vnet create `
-g $RG `
-n $COMPANYVNET `
--address-prefix 172.16.0.0/16 `
--subnet-name company-subnet `
--subnet-prefix 172.16.1.0/24

##################################################
# Azure VNET
##################################################

az network vnet create `
-g $RG `
-n $AZUREVNET `
--address-prefix 10.0.0.0/16 `
--subnet-name web-subnet `
--subnet-prefix 10.0.1.0/24

##################################################
# GatewaySubnet
##################################################

az network vnet subnet create `
-g $RG `
--vnet-name $AZUREVNET `
-n GatewaySubnet `
--address-prefix 10.0.255.0/27

##################################################
# Company VM
##################################################

az vm create `
-g $RG `
-n $COMPANYVM `
--image Ubuntu2204 `
--size Standard_B1s `
--admin-username $USER `
--admin-password $PASS `
--authentication-type password `
--vnet-name $COMPANYVNET `
--subnet company-subnet


##################################################
# Web VM
##################################################

az vm create `
-g $RG `
-n $WEBVM `
--image Ubuntu2204 `
--size Standard_B1s `
--admin-username $USER `
--admin-password $PASS `
--authentication-type password `
--vnet-name $AZUREVNET `
--subnet web-subnet

##################################################
# Open Ports
##################################################

az vm open-port -g $RG -n $COMPANYVM --port 22

az vm open-port -g $RG -n $WEBVM --port 22

az vm open-port -g $RG -n $WEBVM --port 80


##################################################
# VPN Gateway
##################################################

az network vnet-gateway create `
-g $RG `
-n AzureVPNGateway `
--public-ip-address vpn-ip `
--vnet $AZUREVNET `
--gateway-type Vpn `
--vpn-type RouteBased `
--sku VpnGw1

##################################################
# Company VM Public IP
##################################################

$COMPANYPIP=$(az vm list-ip-addresses `
-g $RG `
-n $COMPANYVM `
--query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" `
-o tsv)

##################################################
# Local Network Gateway
##################################################

az network local-gateway create `
-g $RG `
-n CompanyGateway `
--gateway-ip-address $COMPANYPIP `
--local-address-prefixes 172.16.0.0/16

##################################################
# VPN Connection
##################################################

az network vpn-connection create `
-g $RG `
-n CompanyConnection `
--vnet-gateway1 AzureVPNGateway `
--local-gateway2 CompanyGateway `
--shared-key ABC123

##################################################
# Display Connection
##################################################

az network vpn-connection show `
-g VPNDemoRG `
-n CompanyConnection `
--query "{Status:connectionStatus}"