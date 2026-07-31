# ============================================
# Variables
# ============================================
 
$LOCATION = "centralindia"
$RG       = "WebAppFlexRG"
$VNET     = "webapp-vnet"
$DBSUBNET = "postgres-subnet"
$APPSUBNET= "appservice-subnet"
$PLAN     = "web-linux-plan"
$WEBAPP   = "studentportal1369430454"
$SERVER   = "pgsqlblazetestxy"
$DB       = "studentdb"
$USER     = "azureadmin"
$PASS     = "Azure@12345678!"   # NOTE: rotate this and store in Key Vault, don't commit it
 
# ============================================
# Resource Group
# ============================================
 
az group create -n $RG -l $LOCATION
 
# ============================================
# Virtual Network
# ============================================
 
az network vnet create -g $RG -n $VNET --address-prefixes 10.0.0.0/16
 
# ============================================
# PostgreSQL Subnet (delegated to flexible servers)
# ============================================
 
az network vnet subnet create -g $RG --vnet-name $VNET -n $DBSUBNET --address-prefixes 10.0.1.0/24 --delegations Microsoft.DBforPostgreSQL/flexibleServers
 
# ============================================
# App Service Subnet (delegated to server farms)
# ============================================
 
az network vnet subnet create -g $RG --vnet-name $VNET -n $APPSUBNET --address-prefixes 10.0.2.0/24 --delegations Microsoft.Web/serverFarms
 
# ============================================
# Private DNS Zone for the flexible server
# ============================================
 
$DNSZONE = "$SERVER.private.postgres.database.azure.com"
 
az network private-dns zone create -g $RG -n $DNSZONE
 
az network private-dns link vnet create -g $RG -z $DNSZONE -n postgreslink -v $VNET -e false
 
# ============================================
# PostgreSQL Flexible Server (private access)
# ============================================
 
az postgres flexible-server create `
  -g $RG `
  -n $SERVER `
  -l $LOCATION `
  --admin-user $USER `
  --admin-password $PASS `
  --sku-name Standard_B1ms `
  --tier Burstable `
  --version 17 `
  --vnet $VNET `
  --subnet $DBSUBNET `
  --private-dns-zone $DNSZONE
 
# ============================================
# Create Database
# ============================================
 
az postgres flexible-server db create `
  --resource-group $RG `
  --server-name $SERVER `
  --name $DB
 
# ============================================
# Get the REAL PostgreSQL FQDN and use it for DBHOST
# (private-access server -> this is the *.private.* name)
# ============================================
 
$DBHOST = az postgres flexible-server show `
  -g $RG `
  -n $SERVER `
  --query fullyQualifiedDomainName `
  -o tsv
 
Write-Host "Resolved DBHOST = $DBHOST"
 
# ============================================
# App Service Plan
# ============================================
 
az appservice plan create `
  -g $RG `
  -n $PLAN `
  --is-linux `
  --sku B1
 
# ============================================
# Web App
# ============================================
 
az webapp create `
  -g $RG `
  -p $PLAN `
  -n $WEBAPP `
  --runtime "PYTHON:3.12"
 
# ============================================
# VNet Integration
# ============================================
 
az webapp vnet-integration add `
  -g $RG `
  -n $WEBAPP `
  --vnet $VNET `
  --subnet $APPSUBNET
 
# ============================================
# Application Settings  (DBHOST now comes from the server itself)
# ============================================
 
az webapp config appsettings set `
  -g $RG `
  -n $WEBAPP `
  --settings `
  DBHOST="$DBHOST" `
  DBNAME=$DB `
  DBUSER=$USER `
  DBPASSWORD=$PASS `
  SSLMODE=require `
  WEBSITE_VNET_ROUTE_ALL=1 `
  SCM_DO_BUILD_DURING_DEPLOYMENT=true
 
# ============================================
# Startup Command
# ============================================
 
az webapp config set `
  -g $RG `
  -n $WEBAPP `
  --startup-file "startup.sh"
 
# ============================================
# Zip Application  (exclude the script with secrets and any old zip)
# ============================================
 
Compress-Archive `
  -Path app.py, startup.sh, requirements.txt, templates `
  -DestinationPath app.zip `
  -Force
 
# ============================================
# Deploy Application
# ============================================
 
az webapp deployment source config-zip `
  -g $RG `
  -n $WEBAPP `
  --src app.zip
 
# ============================================
# Display Information
# ============================================
 
Write-Host ""
Write-Host "====================================="
Write-Host "Database Host : $DBHOST"
Write-Host "Database      : $DB"
Write-Host "====================================="
 
# ============================================
# Verify PostgreSQL Server
# ============================================
 
az postgres flexible-server show `
  -g $RG `
  -n $SERVER `
  -o table
