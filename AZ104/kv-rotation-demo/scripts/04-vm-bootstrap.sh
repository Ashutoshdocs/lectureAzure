#!/usr/bin/env bash
# Step 4: one-time VM prep. Installs python venv and writes /etc/kvdemo.env
# (URLs and names only; the secret value is never written to disk).
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "
apt-get update -y && apt-get install -y python3-venv
mkdir -p /opt/kvdemo && chown azureuser:azureuser /opt/kvdemo
cat > /etc/kvdemo.env <<EOV
KEYVAULT_URL=https://$KV.vault.azure.net
SECRET_NAME=$SECRET_NAME
QUEUE_ACCOUNT_URL=https://$ST.queue.core.windows.net
QUEUE_NAME=$QUEUE
POLL_SECONDS=60
EOV
echo bootstrap-done" --query "value[0].message" -o tsv

cat <<MSG

Next: add these GitHub repo secrets (Settings -> Secrets and variables -> Actions)
  VM_HOST    = $(vm_ip)
  VM_USER    = azureuser
  VM_SSH_KEY = contents of ~/.ssh/id_rsa
Then push to main (or run the "Deploy to VM" workflow manually).
MSG
