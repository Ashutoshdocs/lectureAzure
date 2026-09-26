#!/usr/bin/env bash
# ------------------------------------------------------------------
# DEMO 3 - PRIVATE LINK SERVICE (PLS)
#
# Lesson: in demo 2, Microsoft was the "provider" of storage.
#         Now WE become the provider. We run our own private web app
#         in vnet-provider (behind an internal Standard Load Balancer),
#         publish it as a Private Link Service, and a consumer in a
#         totally separate, NON-peered VNet reaches it via a private
#         endpoint.
# ------------------------------------------------------------------
source "$(dirname "$0")/env.sh"

step "1. PROVIDER side: internal Standard Load Balancer in snet-backend"
az network lb create -g "$RG" -n lb-provider --sku Standard \
  --vnet-name "$VNET_PROVIDER" --subnet snet-backend \
  --frontend-ip-name fe-internal --backend-pool-name be-pool -o none
az network lb probe create -g "$RG" --lb-name lb-provider -n probe-80 --protocol tcp --port 80 -o none
az network lb rule create -g "$RG" --lb-name lb-provider -n rule-80 --protocol tcp \
  --frontend-port 80 --backend-port 80 --frontend-ip-name fe-internal \
  --backend-pool-name be-pool --probe-name probe-80 -o none
LB_IP=$(az network lb frontend-ip show -g "$RG" --lb-name lb-provider -n fe-internal --query privateIPAddress -o tsv)
info "Provider's internal LB IP: $LB_IP (only reachable INSIDE vnet-provider)"

step "2. PROVIDER side: backend web server VM (tiny Python web server, no internet needed)"
cat > /tmp/cloud-init-backend.yaml <<'EOF'
#cloud-config
write_files:
  - path: /opt/web/index.html
    content: |
      <h1>Hello from the PROVIDER's private app!</h1>
      <p>You reached me through a Private Endpoint -> Private Link Service -> Load Balancer.</p>
      <p>Our two VNets are NOT peered. Magic, right?</p>
  - path: /etc/systemd/system/demo-web.service
    content: |
      [Unit]
      Description=Demo web server
      After=network.target
      [Service]
      ExecStart=/usr/bin/python3 -m http.server 80 --directory /opt/web
      Restart=always
      [Install]
      WantedBy=multi-user.target
runcmd:
  - systemctl daemon-reload
  - systemctl enable --now demo-web
EOF
az network nic create -g "$RG" -n nic-backend --vnet-name "$VNET_PROVIDER" --subnet snet-backend \
  --lb-name lb-provider --lb-address-pools be-pool -o none
az vm create -g "$RG" -n vm-backend --image Ubuntu2204 --size "$VM_SIZE" \
  --nics nic-backend --admin-username azureuser --generate-ssh-keys \
  --custom-data /tmp/cloud-init-backend.yaml -o none

step "3. PROVIDER side: publish the LB as a Private Link Service"
az network private-link-service create -g "$RG" -n pls-provider -l "$LOCATION" \
  --vnet-name "$VNET_PROVIDER" --subnet snet-pls \
  --lb-name lb-provider --lb-frontend-ip-configs fe-internal -o none
PLS_ID=$(az network private-link-service show -g "$RG" -n pls-provider --query id -o tsv)
PLS_ALIAS=$(az network private-link-service show -g "$RG" -n pls-provider --query alias -o tsv)
info "PLS alias (what you'd hand to a customer in another tenant): $PLS_ALIAS"

step "4. CONSUMER side: create a Private Endpoint that points at the PLS"
az network private-endpoint create -g "$RG" -n pe-to-pls \
  --vnet-name "$VNET_CONSUMER" --subnet snet-pe \
  --private-connection-resource-id "$PLS_ID" --connection-name conn-pls -o none
PE_NIC=$(az network private-endpoint show -g "$RG" -n pe-to-pls --query 'networkInterfaces[0].id' -o tsv)
PE_PLS_IP=$(az network nic show --ids "$PE_NIC" --query 'ipConfigurations[0].privateIPAddress' -o tsv)
save_state PE_PLS_IP "$PE_PLS_IP"
info "Consumer reaches the provider app at: $PE_PLS_IP (a 10.1.2.x address in vnet-consumer)"

step "5. PROVIDER side: see (and approve) connection requests"
az network private-link-service show -g "$RG" -n pls-provider \
  --query 'privateEndpointConnections[].{name:name, status:privateLinkServiceConnectionState.status}' -o table
info "Same-subscription requests are auto-approved. Cross-tenant ones would show 'Pending'"
info "and the provider approves with: az network private-link-service connection update ... --connection-status Approved"

info "Waiting 60s for the backend VM to boot and the LB probe to go healthy..."
sleep 60

step "6. TEST from consumer VM"
run_on_vm "echo '--- A) Direct to provider LB ($LB_IP) - should FAIL (VNets not peered):'; curl -s --max-time 5 http://$LB_IP || echo 'TIMEOUT - no route, as expected'; echo; echo '--- B) Via our private endpoint ($PE_PLS_IP) - should WORK:'; curl -s --max-time 10 http://$PE_PLS_IP"

step "DEMO 3 DONE"
info "Key takeaway: PLS is how YOU publish YOUR app so others can build a private endpoint to it."
info "Next: ./04-vnet-injection.sh"
