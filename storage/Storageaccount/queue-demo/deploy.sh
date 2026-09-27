#!/usr/bin/env bash
# Deploys: Resource Group, Storage Account (+ 'orders' and 'orders-poison' queues),
# Ubuntu VM with a system-assigned managed identity, and RBAC so both the VM
# and you can use the queue without keys.
set -euo pipefail
cd "$(dirname "$0")"

LOCATION="${LOCATION:-centralindia}"
RG="${RG:-rg-queue-demo}"
SA="${SA:-stqdemo$(openssl rand -hex 4)}"   # 3-24 chars, lowercase, globally unique
QUEUE="${QUEUE:-orders}"
VM="${VM:-vm-queue-worker}"
VM_SIZE="${VM_SIZE:-Standard_B1s}"
ADMIN="azureuser"
ROLE="Storage Queue Data Contributor"

echo "==> Resource group $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

echo "==> Storage account $SA"
az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false -o none
SA_ID=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)

echo "==> Queues: $QUEUE, $QUEUE-poison"
az storage queue create -n "$QUEUE" --account-name "$SA" --auth-mode key -o none
az storage queue create -n "$QUEUE-poison" --account-name "$SA" --auth-mode key -o none

echo "==> Granting '$ROLE' to you (for running the producer locally)"
USER_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$USER_ID" --assignee-principal-type User \
  --role "$ROLE" --scope "$SA_ID" -o none

echo "==> VM $VM ($VM_SIZE) with managed identity"
az vm create -g "$RG" -n "$VM" -l "$LOCATION" --image Ubuntu2404 --size "$VM_SIZE" \
  --admin-username "$ADMIN" --generate-ssh-keys --assign-identity \
  --public-ip-sku Standard --custom-data cloud-init.yaml -o none
PRINCIPAL_ID=$(az vm show -g "$RG" -n "$VM" --query identity.principalId -o tsv)

echo "==> Granting '$ROLE' to the VM's managed identity"
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "$ROLE" --scope "$SA_ID" -o none

IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

echo "==> Waiting for VM setup (cloud-init) to finish..."
for i in {1..30}; do
  ssh $SSH_OPTS "$ADMIN@$IP" "cloud-init status --wait" >/dev/null 2>&1 && break
  sleep 10
done

echo "==> Copying queue_demo.py to the VM"
scp $SSH_OPTS queue_demo.py "$ADMIN@$IP:/opt/queuedemo/"
ssh $SSH_OPTS "$ADMIN@$IP" "cat > ~/.queuedemo_env <<EOF
export STORAGE_ACCOUNT=$SA
export QUEUE_NAME=$QUEUE
alias qd='/opt/queuedemo/venv/bin/python /opt/queuedemo/queue_demo.py'
EOF
grep -q queuedemo_env ~/.bashrc || echo 'source ~/.queuedemo_env' >> ~/.bashrc"

cat > .env <<EOF
export RG=$RG
export STORAGE_ACCOUNT=$SA
export QUEUE_NAME=$QUEUE
export VM_IP=$IP
EOF

cat <<EOF

============================================================
 Deployed!
   Storage account : $SA
   Queues          : $QUEUE, $QUEUE-poison
   Worker VM       : $VM  ($IP)

 Laptop (producer):  source .env && python queue_demo.py send --count 5
 VM (worker):        ssh $ADMIN@$IP   then   qd worker

 Note: role assignments can take 1-5 minutes to take effect.
 If you get AuthorizationPermissionMismatch, wait and retry.
============================================================
EOF
