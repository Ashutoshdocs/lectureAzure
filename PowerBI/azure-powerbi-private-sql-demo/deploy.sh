#!/usr/bin/env bash
set -euo pipefail

# ---------------- EDIT THESE ----------------
LOCATION="centralindia"
RG="rg-pbi-private-demo"
SQL_SERVER="sqlpbi$(openssl rand -hex 4)"
SQL_ADMIN="labadmin"
SQL_PASSWORD="${blazex@123}"
DB="SalesDemo"
# --------------------------------------------

command -v az >/dev/null || { echo "Azure CLI is required"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Run az login first"; exit 1; }

echo "Creating resource group..."
az group create -n "$RG" -l "$LOCATION" -o none

echo "Creating two VNets..."
az network vnet create -g "$RG" -n vnet-sql-demo -l "$LOCATION" \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name snet-private-endpoints --subnet-prefixes 10.10.1.0/24 -o none

az network vnet create -g "$RG" -n vnet-pbi-gateway-demo -l "$LOCATION" \
  --address-prefixes 10.20.0.0/16 \
  --subnet-name snet-vnet-gateway --subnet-prefixes 10.20.1.0/24 -o none

echo "Delegating gateway subnet..."
az network vnet subnet update -g "$RG" --vnet-name vnet-pbi-gateway-demo \
  -n snet-vnet-gateway \
  --delegations Microsoft.PowerPlatform/vnetaccesslinks -o none

echo "Creating bidirectional VNet peering..."
SQL_VNET_ID=$(az network vnet show -g "$RG" -n vnet-sql-demo --query id -o tsv)
GW_VNET_ID=$(az network vnet show -g "$RG" -n vnet-pbi-gateway-demo --query id -o tsv)

az network vnet peering create -g "$RG" --vnet-name vnet-sql-demo \
  -n sql-to-gateway --remote-vnet "$GW_VNET_ID" --allow-vnet-access -o none
az network vnet peering create -g "$RG" --vnet-name vnet-pbi-gateway-demo \
  -n gateway-to-sql --remote-vnet "$SQL_VNET_ID" --allow-vnet-access -o none

echo "Creating Private DNS zone and linking both VNets..."
az network private-dns zone create -g "$RG" -n privatelink.database.windows.net -o none
az network private-dns link vnet create -g "$RG" \
  -n link-sql-vnet -z privatelink.database.windows.net \
  -v "$SQL_VNET_ID" -e false -o none
az network private-dns link vnet create -g "$RG" \
  -n link-gateway-vnet -z privatelink.database.windows.net \
  -v "$GW_VNET_ID" -e false -o none

echo "Creating Azure SQL logical server and database..."
az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOCATION" \
  -u "$SQL_ADMIN" -p "$SQL_PASSWORD" \
  --enable-public-network false -o none

az sql db create -g "$RG" -s "$SQL_SERVER" -n "$DB" \
  --service-objective Basic -o none

echo "Creating SQL private endpoint..."
SQL_ID=$(az sql server show -g "$RG" -n "$SQL_SERVER" --query id -o tsv)
az network private-endpoint create -g "$RG" -n pe-sql-private \
  --vnet-name vnet-sql-demo --subnet snet-private-endpoints \
  --private-connection-resource-id "$SQL_ID" \
  --group-id sqlServer --connection-name sql-private-connection -o none

echo "Creating private DNS zone group..."
az network private-endpoint dns-zone-group create -g "$RG" \
  --endpoint-name pe-sql-private -n sql-dns-zone-group \
  --private-dns-zone privatelink.database.windows.net \
  --zone-name sql -o none

echo "Waiting briefly for private DNS registration..."
sleep 15

echo "Infrastructure is ready. Seed the database from a host that can reach the private endpoint."
echo "Because SQL public network access is disabled, do NOT run sqlcmd from an unrelated public workstation."
echo "Use an Azure VM in either peered VNet (or an approved private admin host), install sqlcmd, then run:"
echo "sqlcmd -S ${SQL_SERVER}.database.windows.net -d ${DB} -U ${SQL_ADMIN} -P '<password>' -N -C -i sql/01-schema-and-seed.sql"

echo
echo "DEPLOYMENT COMPLETE"
echo "Resource group : $RG"
echo "SQL server FQDN: $SQL_FQDN"
echo "Database       : $DB"
echo "SQL admin      : $SQL_ADMIN"
echo "SQL password   : supplied via SQL_PASSWORD env var or script default (rotate it)"
echo "Gateway VNet   : vnet-pbi-gateway-demo"
echo "Gateway subnet : snet-vnet-gateway"
echo "IMPORTANT: Create the Microsoft-managed VNet data gateway in Power BI/Power Platform UI."
