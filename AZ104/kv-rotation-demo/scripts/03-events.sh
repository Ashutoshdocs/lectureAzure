#!/usr/bin/env bash
# Step 3: Storage Queue + Event Grid so the VM hears about new secret versions.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

az storage account create -n "$ST" -g "$RG" -l "$LOC" --sku Standard_LRS -o none
ST_ID=$(st_id)
az storage queue create -n "$QUEUE" --account-name "$ST" --auth-mode login -o none \
  || az storage queue create -n "$QUEUE" --account-name "$ST" -o none

VM_PRINCIPAL=$(az vm identity show -g "$RG" -n "$VM" --query principalId -o tsv)
az role assignment create --assignee-object-id "$VM_PRINCIPAL" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Queue Data Message Processor" --scope "$ST_ID" -o none

az eventgrid system-topic create -g "$RG" -n kv-topic -l "$LOC" \
  --topic-type Microsoft.KeyVault.vaults --source "$(kv_id)" -o none

az eventgrid system-topic event-subscription create -g "$RG" \
  --system-topic-name kv-topic -n secret-new-version-to-queue \
  --endpoint-type storagequeue \
  --endpoint "$ST_ID/queueservices/default/queues/$QUEUE" \
  --included-event-types Microsoft.KeyVault.SecretNewVersionCreated \
  --subject-begins-with "$SECRET_NAME" -o none

echo "Event Grid -> queue '$QUEUE' is wired up."
