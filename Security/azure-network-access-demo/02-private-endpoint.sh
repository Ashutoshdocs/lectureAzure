#!/usr/bin/env bash
# ------------------------------------------------------------------
# DEMO 2 - PRIVATE ENDPOINT
#
# Lesson: we give an Azure service (a storage account) a PRIVATE IP
#         address INSIDE our VNet (10.1.2.x) and switch its public
#         door off completely. DNS is the magic that makes the same
#         name resolve to the private IP.
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "1. Create storage account $SA_PRIVATE and upload a test file"
az storage account create -g "$RG" -n "$SA_PRIVATE" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false -o none
KEY=$(az storage account keys list -g "$RG" -n "$SA_PRIVATE" --query '[0].value' -o tsv)
echo "Hello! You reached storage through its PRIVATE ENDPOINT (a 10.x address in your VNet)." > /tmp/hello2.txt
az storage container create --account-name "$SA_PRIVATE" --account-key "$KEY" -n demo -o none
az storage blob upload --account-name "$SA_PRIVATE" --account-key "$KEY" \
  -c demo -n hello.txt -f /tmp/hello2.txt --overwrite -o none
SAS=$(az storage blob generate-sas --account-name "$SA_PRIVATE" --account-key "$KEY" \
  -c demo -n hello.txt --permissions r --expiry "$(sas_expiry)" -o tsv)
URL="https://${SA_PRIVATE}.blob.core.windows.net/demo/hello.txt?${SAS}"
SA_ID=$(az storage account show -g "$RG" -n "$SA_PRIVATE" --query id -o tsv)

step "2. Create the Private Endpoint in snet-pe (a network card for storage, inside OUR VNet)"
az network private-endpoint create -g "$RG" -n pe-storage \
  --vnet-name "$VNET_CONSUMER" --subnet snet-pe \
  --private-connection-resource-id "$SA_ID" --group-id blob \
  --connection-name conn-storage -o none
PE_NIC=$(az network private-endpoint show -g "$RG" -n pe-storage --query 'networkInterfaces[0].id' -o tsv)
PE_IP=$(az network nic show --ids "$PE_NIC" --query 'ipConfigurations[0].privateIPAddress' -o tsv)
save_state PE_STORAGE_IP "$PE_IP"
info "Storage now has a private address in our VNet: $PE_IP"

step "3. Private DNS: make '${SA_PRIVATE}.blob.core.windows.net' answer $PE_IP inside our VNet"
az network private-dns zone create -g "$RG" -n privatelink.blob.core.windows.net -o none
az network private-dns link vnet create -g "$RG" --zone-name privatelink.blob.core.windows.net \
  -n link-consumer --virtual-network "$VNET_CONSUMER" --registration-enabled false -o none
az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name pe-storage \
  -n default --private-dns-zone privatelink.blob.core.windows.net --zone-name blob -o none

step "4. Close the public door completely"
az storage account update -g "$RG" -n "$SA_PRIVATE" --public-network-access Disabled -o none
info "Waiting 30s for changes to settle..."
sleep 30

step "5. TEST from YOUR machine / Cloud Shell (the public internet)"
echo "  DNS answer (public world still sees a public IP):"
nslookup "${SA_PRIVATE}.blob.core.windows.net" 2>/dev/null | tail -n 4 || true
echo "  HTTP result:"
curl -s "$URL" | head -c 300; echo
info "Expected: 403 'PublicAccessNotPermitted' - the public door is bricked up."

step "6. TEST from the VM inside our VNet"
run_on_vm "echo 'DNS answer (look - a 10.1.2.x PRIVATE IP):'; nslookup ${SA_PRIVATE}.blob.core.windows.net | tail -n 5; echo 'HTTP result:'; curl -s '$URL'"
info "Expected: DNS -> $PE_IP and the hello message."

step "DEMO 2 DONE"
info "Key takeaway: the SERVICE came to US - it got a private IP in our VNet."
info "Next: ./03-private-link-service.sh"
