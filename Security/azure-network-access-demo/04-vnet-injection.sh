#!/usr/bin/env bash
# ------------------------------------------------------------------
# DEMO 4 - VNET INJECTION
#
# Lesson: the Azure service is DEPLOYED INTO our subnet. The whole
#         thing lives in our VNet: it gets a private IP from snet-aci,
#         obeys our NSGs/routes, can be reached privately AND can
#         reach other things privately. We use Azure Container
#         Instances (ACI) because it's cheap and fast.
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "1. Deploy a container group INTO snet-aci (a delegated subnet)"
az container create -g "$RG" -n aci-injected \
  --image mcr.microsoft.com/azuredocs/aci-helloworld:latest \
  --os-type Linux --cpu 1 --memory 1.5 --ports 80 \
  --vnet "$VNET_CONSUMER" --subnet snet-aci --ip-address Private -o none

ACI_IP=$(az container show -g "$RG" -n aci-injected --query ipAddress.ip -o tsv)
save_state ACI_IP "$ACI_IP"

step "2. Look at what we got"
az container show -g "$RG" -n aci-injected \
  --query '{name:name, ipType:ipAddress.type, privateIp:ipAddress.ip, state:instanceView.state}' -o table
az network vnet subnet show -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-aci \
  --query '{subnet:name, delegatedTo:delegations[0].serviceName}' -o table
info "The container has NO public IP at all. Its IP ($ACI_IP) came from OUR subnet 10.1.3.0/24."

step "3. TEST from the test VM (a neighbour in the same VNet)"
run_on_vm "curl -s --max-time 10 http://$ACI_IP | grep -o '<h1>.*</h1>\|Welcome[^<]*' | head -n 3 || curl -s --max-time 10 http://$ACI_IP | head -c 400"
info "Expected: the ACI hello-world page. It's just another neighbour on our street."

step "4. TEST from the internet"
info "Nothing to test - there is no public address to even try. That's the point."

step "DEMO 4 DONE"
info "Key takeaway: with injection the service MOVES IN. Inbound AND outbound are private."
info "Next: ./05-vnet-integration.sh"
