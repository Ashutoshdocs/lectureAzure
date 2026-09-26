#!/usr/bin/env bash
# ------------------------------------------------------------------
# STEP 0 - Build the "neighbourhood" that every demo uses.
#
#   vnet-consumer 10.1.0.0/16  (OUR network)
#     snet-vm      10.1.1.0/24  test VM lives here (+ NAT gateway for internet)
#     snet-pe      10.1.2.0/24  private endpoints get their IPs here
#     snet-aci     10.1.3.0/24  delegated to Container Instances (VNet injection)
#     snet-appsvc  10.1.4.0/24  delegated to App Service (VNet integration)
#
#   vnet-provider 10.2.0.0/16  (SOMEONE ELSE's network, NOT peered)
#     snet-backend 10.2.1.0/24  provider's private web server + load balancer
#     snet-pls     10.2.2.0/24  Private Link Service NAT IPs
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "Creating resource group $RG in $LOCATION"
az group create -n "$RG" -l "$LOCATION" -o none

step "Creating NAT gateway (gives the test VM outbound internet in a clean, modern way)"
az network public-ip create -g "$RG" -n pip-nat --sku Standard -o none
az network nat gateway create -g "$RG" -n nat-demo --public-ip-addresses pip-nat -o none

step "Creating consumer VNet (10.1.0.0/16) and its 4 subnets"
az network vnet create -g "$RG" -n "$VNET_CONSUMER" --address-prefixes 10.1.0.0/16 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-vm \
  --address-prefixes 10.1.1.0/24 --nat-gateway nat-demo -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-pe \
  --address-prefixes 10.1.2.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-aci \
  --address-prefixes 10.1.3.0/24 --delegations Microsoft.ContainerInstance/containerGroups -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-appsvc \
  --address-prefixes 10.1.4.0/24 --delegations Microsoft.Web/serverFarms -o none

step "Creating provider VNet (10.2.0.0/16) - deliberately NOT peered with consumer"
az network vnet create -g "$RG" -n "$VNET_PROVIDER" --address-prefixes 10.2.0.0/16 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_PROVIDER" -n snet-backend \
  --address-prefixes 10.2.1.0/24 -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET_PROVIDER" -n snet-pls \
  --address-prefixes 10.2.2.0/24 --private-link-service-network-policies Disabled -o none

step "Creating the test VM (no public IP - we talk to it via 'run-command')"
az vm create -g "$RG" -n "$TEST_VM" --image Ubuntu2204 --size "$VM_SIZE" \
  --vnet-name "$VNET_CONSUMER" --subnet snet-vm \
  --public-ip-address "" --nsg "" \
  --admin-username azureuser --generate-ssh-keys -o none

info "Installing dnsutils (nslookup) on the test VM"
run_on_vm "apt-get update -qq && apt-get install -y -qq dnsutils curl >/dev/null && echo tools-ready"

step "Setup complete. Neighbourhood is ready."
info "Test VM private IP: $(az vm list-ip-addresses -g "$RG" -n "$TEST_VM" --query '[0].virtualMachine.network.privateIpAddresses[0]' -o tsv)"
info "Next: ./01-public-endpoint-vnet-restricted.sh"
