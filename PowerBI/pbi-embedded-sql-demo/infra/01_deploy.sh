#!/usr/bin/env bash
# =====================================================================
# 01_deploy.sh — Azure infrastructure
#   VNet + subnets, NAT gateway, Azure SQL logical server (Entra-only auth,
#   public access disabled), Private Endpoint + Private DNS, gateway VM,
#   Azure Bastion, Power BI Embedded capacity (A SKU), Key Vault,
#   App Service (Linux, Node 20) for the embedding web app.
# Run 00_identity.sh first. Output: infra/.infra.env
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
source ./.identity.env

# ---------- variables (edit) ----------
LOC="centralindia"
RG="rg-pbi-embedded-demo"
SUFFIX=${SUFFIX:-$RANDOM}
SQL_SERVER="sql-pbiemb-$SUFFIX"
SQL_DB="SalesDemo"
VNET="vnet-pbiemb"
VM_NAME="vm-pbi-gateway"
VM_ADMIN="azureadmin"
CAPACITY="pbiembcap$SUFFIX"          # lowercase letters/digits only, 3-63 chars
CAPACITY_SKU="A1"                    # A1 = cheapest; VNet data gateway needs A4+ (see README)
KV="kv-pbiemb-$SUFFIX"
PLAN="asp-pbiemb"
WEBAPP="app-pbiemb-$SUFFIX"
read -rsp "Password for gateway VM local admin: " VM_PASSWORD; echo

az extension add --name powerbidedicated --upgrade -y -o none

echo ">> Resource group"
az group create -n "$RG" -l "$LOC" -o none

echo ">> VNet + subnets"
az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.30.0.0/16 \
  --subnet-name snet-private-endpoints --subnet-prefixes 10.30.1.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-gateway-vm    --address-prefixes 10.30.2.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n AzureBastionSubnet --address-prefixes 10.30.4.0/26 -o none

echo ">> NAT gateway (gateway VM needs outbound 443 to Power BI / Azure Relay; no inbound)"
az network public-ip create -g "$RG" -n pip-nat --sku Standard -o none
az network nat gateway create -g "$RG" -n nat-pbiemb --public-ip-addresses pip-nat -o none
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n snet-gateway-vm --nat-gateway nat-pbiemb -o none

echo ">> Azure SQL logical server — Microsoft Entra-only authentication"
az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOC" \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "$SQL_ADMINS_GROUP" \
  --external-admin-sid "$SQL_ADMINS_GROUP_ID" \
  --minimal-tls-version 1.2 -o none

az sql db create -g "$RG" -s "$SQL_SERVER" -n "$SQL_DB" \
  --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 1 \
  --auto-pause-delay 60 --backup-storage-redundancy Local -o none

echo ">> Disable public network access"
az sql server update -g "$RG" -n "$SQL_SERVER" --enable-public-network false -o none

echo ">> Private endpoint + private DNS"
SQL_ID=$(az sql server show -g "$RG" -n "$SQL_SERVER" --query id -o tsv)
az network private-endpoint create -g "$RG" -n pe-sql \
  --vnet-name "$VNET" --subnet snet-private-endpoints \
  --private-connection-resource-id "$SQL_ID" --group-id sqlServer \
  --connection-name pe-sql-conn -o none
az network private-dns zone create -g "$RG" -n privatelink.database.windows.net -o none
az network private-dns link vnet create -g "$RG" --zone-name privatelink.database.windows.net \
  -n link-vnet --virtual-network "$VNET" --registration-enabled false -o none
az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name pe-sql -n default \
  --private-dns-zone privatelink.database.windows.net --zone-name sql -o none

echo ">> Gateway VM (no public IP)"
az vm create -g "$RG" -n "$VM_NAME" --image Win2022Datacenter --size Standard_D4s_v5 \
  --vnet-name "$VNET" --subnet snet-gateway-vm --public-ip-address "" --nsg "" \
  --admin-username "$VM_ADMIN" --admin-password "$VM_PASSWORD" -o none

echo ">> Azure Bastion"
az network public-ip create -g "$RG" -n pip-bastion --sku Standard -o none
az network bastion create -g "$RG" -n bas-pbiemb --vnet-name "$VNET" \
  --public-ip-address pip-bastion --sku Basic -o none

echo ">> Power BI Embedded capacity ($CAPACITY_SKU)"
az powerbi embedded-capacity create -g "$RG" -n "$CAPACITY" -l "$LOC" \
  --sku-name "$CAPACITY_SKU" --sku-tier PBIE_Azure \
  --administration-members "$ADMIN_UPN" -o none

echo ">> Key Vault (stores the embed app secret)"
az keyvault create -g "$RG" -n "$KV" -l "$LOC" --enable-rbac-authorization true -o none
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
az role assignment create --assignee "$ADMIN_OID" --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none
sleep 30   # RBAC propagation
az keyvault secret set --vault-name "$KV" -n pbi-embed-secret --value "$EMBED_SECRET" -o none

echo ">> App Service (Linux, Node 20) with system-assigned managed identity"
az appservice plan create -g "$RG" -n "$PLAN" --is-linux --sku B1 -o none
az webapp create -g "$RG" -p "$PLAN" -n "$WEBAPP" --runtime "NODE:20-lts" -o none
az webapp identity assign -g "$RG" -n "$WEBAPP" -o none
WEBAPP_MI=$(az webapp show -g "$RG" -n "$WEBAPP" --query identity.principalId -o tsv)
az role assignment create --assignee-object-id "$WEBAPP_MI" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID" -o none

PE_IP=$(az network private-endpoint show -g "$RG" -n pe-sql --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv)
CAPACITY_ID=$(az powerbi embedded-capacity show -g "$RG" -n "$CAPACITY" --query id -o tsv)

cat > .infra.env <<EOF
RG=$RG
LOC=$LOC
SQL_SERVER_FQDN=$SQL_SERVER.database.windows.net
SQL_DB=$SQL_DB
PE_IP=$PE_IP
CAPACITY_NAME=$CAPACITY
CAPACITY_ARM_ID=$CAPACITY_ID
KEY_VAULT=$KV
WEBAPP=$WEBAPP
EOF

echo
echo "================ DONE ================"
cat .infra.env
echo "Next: README step 3 (load dataset from the VM) and step 4 (install gateway)."
