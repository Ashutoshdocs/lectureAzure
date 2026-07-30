# ============================================
# Variables
# ============================================

$LOCATION = "centralindia"

$RG = "WebAppFlexRG"

$VNET = "webapp-vnet"

$DBSUBNET = "postgres-subnet"

$APPSUBNET = "appservice-subnet"

$PLAN = "web-linux-plan"

$WEBAPP = "studentportal1369430454"

$SERVER = "pgsql$(Get-Random)"

$DB = "studentdb"

$USER = "azureadmin"

$PASS = "Azure@12345678!"

# ============================================
# Resource Group
# ============================================

az group create -n $RG -l $LOCATION

# ============================================
# Virtual Network
# ============================================

az network vnet create -g $RG -n $VNET --address-prefixes 10.0.0.0/16

# ============================================
# PostgreSQL Subnet
# ============================================

az network vnet subnet create -g $RG --vnet-name $VNET -n $DBSUBNET --address-prefixes 10.0.1.0/24 --delegations Microsoft.DBforPostgreSQL/flexibleServers

# ============================================
# App Service Subnet
# ============================================

az network vnet subnet create -g $RG --vnet-name $VNET -n $APPSUBNET --address-prefixes 10.0.2.0/24 --delegations Microsoft.Web/serverFarms

# ============================================
# PostgreSQL Flexible Server
# (Azure creates Private DNS automatically)
# ============================================
$DNSZONE = "$SERVER.private.postgres.database.azure.com"

az network private-dns zone create -g $RG -n $DNSZONE


az network private-dns link vnet create -g $RG -z $DNSZONE -n postgreslink -v $VNET -e false



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
# Get PostgreSQL Hostname
# ============================================

az postgres flexible-server show `
-g $RG `
-n $SERVER `
--query fullyQualifiedDomainName `
-o tsv

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
# Application Settings
# ============================================

az webapp config appsettings set `
-g $RG `
-n $WEBAPP `
--settings `
DBHOST="pgsql1405156724.postgres.database.azure.com" `
DBNAME=$DB `
DBUSER=$USER `
DBPASSWORD=$PASS `
SSLMODE=require `
SCM_DO_BUILD_DURING_DEPLOYMENT=true

# ============================================
# Startup Command
# ============================================

az webapp config set `
-g $RG `
-n $WEBAPP `
--startup-file startup.sh

# ============================================
# Zip Application
# ============================================

Compress-Archive `
-Path * `
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
Write-Host "Database Host : $HOST"
Write-Host "Database : $DB"
Write-Host "====================================="

# ============================================
# Verify PostgreSQL Server
# ============================================

az postgres flexible-server show `
-g $RG `
-n $SERVER `
-o table