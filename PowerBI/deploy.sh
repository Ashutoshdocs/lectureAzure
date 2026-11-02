#!/usr/bin/env bash
# =====================================================================
# deploy.sh — Azure SQL logical server + Private Endpoint + Power BI gateway VM
# Prereqs: Azure CLI >= 2.60, logged in (az login), Owner/Contributor on subscription,
#          an Entra ID group to be SQL admin (sg-sql-admins).
# =====================================================================
set -euo pipefail

# ---------- variables (edit) ----------
LOC="centralindia"
RG="rg-pbi-sql-demo"
SUFFIX=$RANDOM
SQL_SERVER="sql-pbi-demo-$SUFFIX"        # becomes sql-pbi-demo-xxxx.database.windows.net
SQL_DB="SalesDemo"
VNET="vnet-pbi-demo"
VNET_CIDR="10.20.0.0/16"
SNET_PE="snet-private-endpoints";   SNET_PE_CIDR="10.20.1.0/24"
SNET_GW="snet-gateway-vm";          SNET_GW_CIDR="10.20.2.0/24"
SNET_VNGW="snet-pbi-vnet-gateway";  SNET_VNGW_CIDR="10.20.3.0/27"   # optional (VNet data gateway)
SNET_BASTION="AzureBastionSubnet";  SNET_BASTION_CIDR="10.20.4.0/26"
VM_NAME="vm-pbi-gateway"
VM_ADMIN="azureadmin"
read -rsp "Password for gateway VM local admin: " VM_PASSWORD; echo

SQL_ADMIN_GROUP="sg-sql-admins"          # Entra ID group that will be SQL Entra admin
SQL_ADMIN_SID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv)

echo ">> Resource group"
az group create -n "$RG" -l "$LOC" -o none

echo ">> Network: VNet + subnets"
az network vnet create -g "$RG" -n "$VNET" --address-prefixes "$VNET_CIDR" \
  --subnet-name "$SNET_PE" --subnet-prefixes "$SNET_PE_CIDR" -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_GW"      --address-prefixes "$SNET_GW_CIDR" -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_BASTION" --address-prefixes "$SNET_BASTION_CIDR" -o none

# Optional: subnet delegated to Power Platform for the managed VNet data gateway
az provider register --namespace Microsoft.PowerPlatform -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_VNGW" \
  --address-prefixes "$SNET_VNGW_CIDR" --delegations Microsoft.PowerPlatform/vnetaccesslinks -o none

echo ">> NAT gateway (explicit outbound for the gateway VM -> Power BI / Azure Relay over 443)"
az network public-ip create -g "$RG" -n pip-nat --sku Standard -o none
az network nat gateway create -g "$RG" -n nat-pbi --public-ip-addresses pip-nat -o none
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET_GW" --nat-gateway nat-pbi -o none

echo ">> SQL logical server (Microsoft Entra-only authentication)"
az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOC" \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "$SQL_ADMIN_GROUP" \
  --external-admin-sid "$SQL_ADMIN_SID" \
  --minimal-tls-version 1.2 -o none

echo ">> Database (serverless, auto-pause to save cost)"
az sql db create -g "$RG" -s "$SQL_SERVER" -n "$SQL_DB" \
  --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 1 \
  --auto-pause-delay 60 --backup-storage-redundancy Local -o none

echo ">> Disable public network access"
az sql server update -g "$RG" -n "$SQL_SERVER" --enable-public-network false -o none

echo ">> Private endpoint for SQL"
SQL_ID=$(az sql server show -g "$RG" -n "$SQL_SERVER" --query id -o tsv)
az network private-endpoint create -g "$RG" -n pe-sql \
  --vnet-name "$VNET" --subnet "$SNET_PE" \
  --private-connection-resource-id "$SQL_ID" \
  --group-id sqlServer --connection-name pe-sql-conn -o none

echo ">> Private DNS zone + VNet link + zone group"
az network private-dns zone create -g "$RG" -n privatelink.database.windows.net -o none
az network private-dns link vnet create -g "$RG" --zone-name privatelink.database.windows.net \
  -n link-$VNET --virtual-network "$VNET" --registration-enabled false -o none
az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name pe-sql \
  -n default --private-dns-zone privatelink.database.windows.net --zone-name sql -o none

echo ">> Gateway VM (no public IP) — host for On-premises data gateway, SSMS, Power BI Desktop"
az vm create -g "$RG" -n "$VM_NAME" --image Win2022Datacenter --size Standard_D4s_v5 \
  --vnet-name "$VNET" --subnet "$SNET_GW" --public-ip-address "" --nsg "" \
  --admin-username "$VM_ADMIN" --admin-password "$VM_PASSWORD" -o none

echo ">> Azure Bastion (secure RDP to the VM)"
az network public-ip create -g "$RG" -n pip-bastion --sku Standard -o none
az network bastion create -g "$RG" -n bas-pbi --vnet-name "$VNET" --public-ip-address pip-bastion --sku Basic -o none

echo
echo "================ DONE ================"
echo "SQL server FQDN : $SQL_SERVER.database.windows.net"
echo "Database        : $SQL_DB"
echo "PE private IP   : $(az network private-endpoint show -g $RG -n pe-sql --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv)"
echo "Next: README §5 (load dataset.sql from the VM) and §6 (install gateway)."
