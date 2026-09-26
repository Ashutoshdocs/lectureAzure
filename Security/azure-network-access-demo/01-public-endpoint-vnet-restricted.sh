#!/usr/bin/env bash
# ------------------------------------------------------------------
# DEMO 1 - PUBLIC ENDPOINT, allowed ONLY from a particular VNet/subnet
#          (Service Endpoint + resource firewall "virtual network rule")
#
# Lesson: the storage account KEEPS its public address. We just put a
#         bouncer at the door who only lets in traffic arriving from
#         snet-vm. Everyone else on the internet gets 403.
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "1. Create storage account $SA_PUBLIC (public, open to everyone for now)"
az storage account create -g "$RG" -n "$SA_PUBLIC" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false -o none
KEY=$(az storage account keys list -g "$RG" -n "$SA_PUBLIC" --query '[0].value' -o tsv)

info "Upload a test file while the door is still open"
echo "Hello! You reached the PUBLIC endpoint - and the firewall let you in." > /tmp/hello1.txt
az storage container create --account-name "$SA_PUBLIC" --account-key "$KEY" -n demo -o none
az storage blob upload --account-name "$SA_PUBLIC" --account-key "$KEY" \
  -c demo -n hello.txt -f /tmp/hello1.txt --overwrite -o none

SAS=$(az storage blob generate-sas --account-name "$SA_PUBLIC" --account-key "$KEY" \
  -c demo -n hello.txt --permissions r --expiry "$(sas_expiry)" -o tsv)
URL="https://${SA_PUBLIC}.blob.core.windows.net/demo/hello.txt?${SAS}"

step "2. Turn on the Service Endpoint for Microsoft.Storage on snet-vm"
info "(this gives snet-vm an 'express lane' onto the Azure backbone and stamps its identity on traffic)"
az network vnet subnet update -g "$RG" --vnet-name "$VNET_CONSUMER" -n snet-vm \
  --service-endpoints Microsoft.Storage -o none

step "3. Configure the storage firewall: DENY everyone, ALLOW snet-vm"
az storage account update -g "$RG" -n "$SA_PUBLIC" --default-action Deny -o none
az storage account network-rule add -g "$RG" --account-name "$SA_PUBLIC" \
  --vnet-name "$VNET_CONSUMER" --subnet snet-vm -o none

info "Waiting 60s for firewall rules to propagate..."
sleep 60

step "4. TEST from YOUR machine / Cloud Shell (the public internet)"
echo "  DNS answer (note: a PUBLIC IP):"
nslookup "${SA_PUBLIC}.blob.core.windows.net" 2>/dev/null | tail -n 4 || true
echo "  HTTP result:"
curl -s "$URL" | head -c 300; echo
info "Expected: 403 'AuthorizationFailure' - the bouncer turned you away."

step "5. TEST from the VM inside snet-vm"
run_on_vm "echo 'DNS answer (still a PUBLIC IP!):'; nslookup ${SA_PUBLIC}.blob.core.windows.net | tail -n 4; echo 'HTTP result:'; curl -s '$URL'"
info "Expected: the hello message. Same public address, but you were on the guest list."

step "DEMO 1 DONE"
info "Key takeaway: address stayed PUBLIC. Only the *who is allowed* changed."
info "Next: ./02-private-endpoint.sh"
