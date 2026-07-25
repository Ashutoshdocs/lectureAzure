#!/usr/bin/env bash
# =====================================================================
#  deploy.sh — deploy the VMSS dashboard with pure Azure CLI (no Bicep)
#  Works in Azure Cloud Shell (bash) or any machine with `az` installed.
#  Usage:  ./deploy.sh
#  Override defaults with env vars, e.g.:
#     RG=my-rg LOCATION=eastus INSTANCES=3 ./deploy.sh
# =====================================================================
set -euo pipefail

# ---- Settings (override via environment) ----------------------------
RG="${RG:-vmss-demo-rg}"
LOCATION="${LOCATION:-centralindia}"
PROJECT="${PROJECT:-vmssdemo}"
VM_SKU="${VM_SKU:-Standard_B1s}"
INSTANCES="${INSTANCES:-2}"
ADMIN_USER="${ADMIN_USER:-azureuser}"

VNET="${PROJECT}-vnet"
SUBNET="default"
NSG="${PROJECT}-nsg"
PIP="${PROJECT}-pip"
LB="${PROJECT}-lb"
VMSS="${PROJECT}-vmss"
FE="frontend"
BEPOOL="bepool"
PROBE="httpProbe"

# cloud-init.yaml must sit next to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="${SCRIPT_DIR}/cloud-init.yaml"

# ---- Preflight ------------------------------------------------------
command -v az >/dev/null 2>&1 || { echo "Azure CLI not found. Install: https://aka.ms/azcli"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Not signed in. Run 'az login' first."; exit 1; }
[ -f "$CLOUD_INIT" ] || { echo "cloud-init.yaml not found next to this script."; exit 1; }

read -rsp "Enter a VM admin password (min 12 chars, mixed complexity): " ADMIN_PW; echo
[ "${#ADMIN_PW}" -ge 12 ] || { echo "Password must be at least 12 characters."; exit 1; }

echo ">> Subscription: $(az account show --query name -o tsv)"

# ---- Resource group -------------------------------------------------
echo ">> Creating resource group '$RG' ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

# ---- NSG (allow HTTP 80 + SSH 22) -----------------------------------
echo ">> Creating NSG and rules"
az network nsg create -g "$RG" -n "$NSG" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-HTTP \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 80 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-SSH \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 22 -o none

# ---- VNet + subnet (attach NSG to subnet) ---------------------------
echo ">> Creating VNet and subnet"
az network vnet create -g "$RG" -n "$VNET" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefixes 10.0.0.0/24 -o none
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
  --network-security-group "$NSG" -o none

# ---- Public IP + Standard Load Balancer -----------------------------
echo ">> Creating public IP and Standard load balancer"
az network public-ip create -g "$RG" -n "$PIP" \
  --sku Standard --allocation-method Static -o none
az network lb create -g "$RG" -n "$LB" --sku Standard \
  --public-ip-address "$PIP" \
  --frontend-ip-name "$FE" \
  --backend-pool-name "$BEPOOL" -o none

# ---- Health probe + HTTP rule ---------------------------------------
echo ">> Adding probe and HTTP rule (80 -> 80)"
az network lb probe create -g "$RG" --lb-name "$LB" -n "$PROBE" \
  --protocol Tcp --port 80 -o none
az network lb rule create -g "$RG" --lb-name "$LB" -n httpRule \
  --protocol Tcp --frontend-port 80 --backend-port 80 \
  --frontend-ip "$FE" --backend-pool-name "$BEPOOL" \
  --probe-name "$PROBE" --disable-outbound-snat true -o none

# ---- Outbound rule (internet access for cloud-init) -----------------
echo ">> Adding outbound rule (so instances can install NGINX)"
az network lb outbound-rule create -g "$RG" --lb-name "$LB" -n outbound \
  --frontend-ip-configs "$FE" --address-pool "$BEPOOL" \
  --protocol All --idle-timeout 4 -o none

# ---- VM Scale Set ---------------------------------------------------
echo ">> Creating VM Scale Set (this is the slow part)"
az vmss create -g "$RG" -n "$VMSS" \
  --orchestration-mode Uniform \
  --image Ubuntu2204 \
  --vm-sku "$VM_SKU" \
  --instance-count "$INSTANCES" \
  --admin-username "$ADMIN_USER" \
  --admin-password "$ADMIN_PW" \
  --vnet-name "$VNET" --subnet "$SUBNET" \
  --lb "$LB" --backend-pool-name "$BEPOOL" \
  --upgrade-policy-mode manual \
  --custom-data "$CLOUD_INIT" \
  --computer-name-prefix vmss \
  -o none

ADMIN_PW=""  # drop the plaintext password

# ---- Result ---------------------------------------------------------
IP="$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)"
echo ""
echo "=================================================="
echo " Deployment complete!"
echo " Public IP : $IP"
echo " Dashboard : http://$IP"
echo "=================================================="
echo ""
echo "Give cloud-init ~2-3 min to install NGINX, then open the URL."
echo "Next: enable autoscale ->  ./autoscale.sh    (or autoscale.ps1)"
