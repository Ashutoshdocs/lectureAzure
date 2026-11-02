
#!/usr/bin/env bash
set -Eeuo pipefail
export MSYS_NO_PATHCONV=1

# ==========================================================
# Azure Power BI Embedded + Azure SQL Private Endpoint
# Two VNets + VNet Peering + Private DNS
# ==========================================================

# ---------------- CONFIGURATION ----------------

LOCATION="centralindia"
RG="rg-pbi-private-demo"

# Set SQL_SERVER as an environment variable to reuse
# the same server name when rerunning this script.
SQL_SERVER="${SQL_SERVER:-sqlpbi$(openssl rand -hex 4)}"

SQL_ADMIN="labadmin"
DB="SalesDemo"

# Enter password through environment variable or prompt
if [[ -z "${SQL_PASSWORD:-}" ]]; then
    read -rsp "Enter Azure SQL administrator password: " SQL_PASSWORD
    echo
fi

if [[ -z "$SQL_PASSWORD" ]]; then
    echo "ERROR: SQL password cannot be empty."
    exit 1
fi

SQL_FQDN="${SQL_SERVER}.database.windows.net"

# ---------------- VALIDATION ----------------

command -v az >/dev/null || {
    echo "ERROR: Azure CLI is required."
    exit 1
}

command -v openssl >/dev/null || {
    echo "ERROR: OpenSSL is required."
    exit 1
}

az account show >/dev/null 2>&1 || {
    echo "ERROR: Run az login first."
    exit 1
}

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "=========================================="
echo "Azure Power BI Private SQL Deployment"
echo "=========================================="
echo "Subscription : $SUBSCRIPTION_ID"
echo "Location     : $LOCATION"
echo "Resource Group: $RG"
echo "SQL Server   : $SQL_SERVER"
echo "Database     : $DB"
echo "=========================================="

# ---------------- RESOURCE GROUP ----------------

echo "[1/10] Creating Resource Group..."

az group create \
    --name "$RG" \
    --location "$LOCATION" \
    -o none

# ---------------- VNets ----------------

echo "[2/10] Creating SQL VNet..."

az network vnet create \
    --resource-group "$RG" \
    --name vnet-sql-demo \
    --location "$LOCATION" \
    --address-prefixes 10.10.0.0/16 \
    --subnet-name snet-private-endpoints \
    --subnet-prefixes 10.10.1.0/24 \
    -o none

echo "[3/10] Creating Gateway VNet..."

az network vnet create \
    --resource-group "$RG" \
    --name vnet-pbi-gateway-demo \
    --location "$LOCATION" \
    --address-prefixes 10.20.0.0/16 \
    --subnet-name snet-vnet-gateway \
    --subnet-prefixes 10.20.1.0/24 \
    -o none

# ---------------- GATEWAY DELEGATION ----------------

echo "[4/10] Configuring Gateway subnet delegation..."

az network vnet subnet update \
    --resource-group "$RG" \
    --vnet-name vnet-pbi-gateway-demo \
    --name snet-vnet-gateway \
    --delegations Microsoft.PowerPlatform/vnetaccesslinks \
    -o none

# ---------------- VNET RESOURCE IDS ----------------

echo "Getting correct VNet resource IDs..."

SQL_VNET_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Network/virtualNetworks/vnet-sql-demo"

GW_VNET_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Network/virtualNetworks/vnet-pbi-gateway-demo"

echo "SQL VNet ID: $SQL_VNET_ID"
echo "Gateway VNet ID: $GW_VNET_ID"

# Validate both VNets

az network vnet show --ids "$SQL_VNET_ID" -o none
az network vnet show --ids "$GW_VNET_ID" -o none

# ---------------- VNET PEERING ----------------

echo "[5/10] Configuring bidirectional VNet peering..."

if ! az network vnet peering show \
    -g "$RG" \
    --vnet-name vnet-sql-demo \
    -n sql-to-gateway >/dev/null 2>&1; then

    az network vnet peering create \
        -g "$RG" \
        --vnet-name vnet-sql-demo \
        -n sql-to-gateway \
        --remote-vnet "$GW_VNET_ID" \
        --allow-vnet-access \
        -o none
else
    echo "SQL-to-Gateway peering already exists."
fi

if ! az network vnet peering show \
    -g "$RG" \
    --vnet-name vnet-pbi-gateway-demo \
    -n gateway-to-sql >/dev/null 2>&1; then

    az network vnet peering create \
        -g "$RG" \
        --vnet-name vnet-pbi-gateway-demo \
        -n gateway-to-sql \
        --remote-vnet "$SQL_VNET_ID" \
        --allow-vnet-access \
        -o none
else
    echo "Gateway-to-SQL peering already exists."
fi

# ---------------- PRIVATE DNS ----------------

echo "[6/10] Creating Private DNS zone..."

az network private-dns zone create \
    -g "$RG" \
    -n privatelink.database.windows.net \
    -o none

echo "Linking SQL VNet to Private DNS..."

if ! az network private-dns link vnet show \
    -g "$RG" \
    -z privatelink.database.windows.net \
    -n link-sql-vnet >/dev/null 2>&1; then

    az network private-dns link vnet create \
        -g "$RG" \
        -n link-sql-vnet \
        -z privatelink.database.windows.net \
        -v "$SQL_VNET_ID" \
        -e false \
        -o none
fi

echo "Linking Gateway VNet to Private DNS..."

if ! az network private-dns link vnet show \
    -g "$RG" \
    -z privatelink.database.windows.net \
    -n link-gateway-vnet >/dev/null 2>&1; then

    az network private-dns link vnet create \
        -g "$RG" \
        -n link-gateway-vnet \
        -z privatelink.database.windows.net \
        -v "$GW_VNET_ID" \
        -e false \
        -o none
fi

# ---------------- SQL SERVER ----------------

echo "[7/10] Creating Azure SQL logical server..."

if ! az sql server show \
    -g "$RG" \
    -n "$SQL_SERVER" >/dev/null 2>&1; then

    az sql server create \
        -g "$RG" \
        -n "$SQL_SERVER" \
        -l "$LOCATION" \
        -u "$SQL_ADMIN" \
        -p "$SQL_PASSWORD" \
        --enable-public-network false \
        -o none

else
    echo "SQL Server already exists."
fi

echo "Ensuring public network access is disabled..."

az sql server update \
    -g "$RG" \
    -n "$SQL_SERVER" \
    --enable-public-network false \
    -o none

# ---------------- SQL DATABASE ----------------

echo "[8/10] Creating SQL database..."

if ! az sql db show \
    -g "$RG" \
    -s "$SQL_SERVER" \
    -n "$DB" >/dev/null 2>&1; then

    az sql db create \
        -g "$RG" \
        -s "$SQL_SERVER" \
        -n "$DB" \
        --service-objective Basic \
        -o none

else
    echo "Database already exists."
fi

SQL_ID=$(az sql server show \
    -g "$RG" \
    -n "$SQL_SERVER" \
    --query id -o tsv)

# ---------------- PRIVATE ENDPOINT ----------------

echo "[9/10] Creating SQL Private Endpoint..."

if ! az network private-endpoint show \
    -g "$RG" \
    -n pe-sql-private >/dev/null 2>&1; then

    az network private-endpoint create \
        -g "$RG" \
        -n pe-sql-private \
        --vnet-name vnet-sql-demo \
        --subnet snet-private-endpoints \
        --private-connection-resource-id "$SQL_ID" \
        --group-id sqlServer \
        --connection-name sql-private-connection \
        -o none

else
    echo "Private Endpoint already exists."
fi

# ---------------- PRIVATE DNS ZONE GROUP ----------------

echo "Configuring Private Endpoint DNS zone group..."

if ! az network private-endpoint dns-zone-group show \
    -g "$RG" \
    --endpoint-name pe-sql-private \
    -n sql-dns-zone-group >/dev/null 2>&1; then

    az network private-endpoint dns-zone-group create \
        -g "$RG" \
        --endpoint-name pe-sql-private \
        -n sql-dns-zone-group \
        --private-dns-zone privatelink.database.windows.net \
        --zone-name sql \
        -o none
else
    echo "Private DNS zone group already exists."
fi

# ---------------- VALIDATION ----------------

echo "[10/10] Validating deployment..."

echo "Checking VNet peering..."

az network vnet peering list \
    -g "$RG" \
    --vnet-name vnet-sql-demo \
    --query "[].{Name:name,State:peeringState}" \
    -o table

az network vnet peering list \
    -g "$RG" \
    --vnet-name vnet-pbi-gateway-demo \
    --query "[].{Name:name,State:peeringState}" \
    -o table

echo "Checking Private Endpoint..."

az network private-endpoint show \
    -g "$RG" \
    -n pe-sql-private \
    --query "{Name:name,State:provisioningState}" \
    -o table

echo "Checking SQL public access..."

az sql server show \
    -g "$RG" \
    -n "$SQL_SERVER" \
    --query "{Server:name,PublicAccess:publicNetworkAccess}" \
    -o table

# ---------------- FINAL OUTPUT ----------------

echo
echo "=========================================="
echo "AZURE INFRASTRUCTURE DEPLOYMENT COMPLETED"
echo "=========================================="

echo "Resource Group : $RG"
echo "SQL Server     : $SQL_SERVER"
echo "SQL FQDN       : $SQL_FQDN"
echo "Database       : $DB"
echo "SQL Admin      : $SQL_ADMIN"
echo "SQL Password   : [not displayed]"
echo
echo "SQL VNet       : vnet-sql-demo"
echo "Gateway VNet   : vnet-pbi-gateway-demo"
echo "Gateway Subnet : snet-vnet-gateway"
echo
echo "Private DNS    : privatelink.database.windows.net"
echo "Private Access : Enabled"
echo "Public SQL     : Disabled"
echo
echo "NEXT STEPS:"
echo "1. Create the Microsoft-managed VNet Data Gateway."
echo "2. Use vnet-pbi-gateway-demo."
echo "3. Select snet-vnet-gateway."
echo "4. Configure Azure SQL connection."
echo "5. Import sql/01-schema-and-seed.sql from a private network host."
echo "6. Connect Power BI semantic model to the VNet gateway."
echo
echo "SQL FQDN: $SQL_FQDN"
echo "=========================================="
