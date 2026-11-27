# Practical 2 – Random VM credentials, existing Key Vault, Bastion and managed identity

## Learning objectives

- Generate a random Linux VM username and password in Bash.
- Store the password as a secret in an **existing** Azure Key Vault.
- Deploy an Ubuntu VM with a system-assigned managed identity.
- Deploy Azure Bastion and connect to a VM that has no public IP.
- Use the VM's managed identity to retrieve a Key Vault secret.

## Important design and security notes

- The Key Vault is **not created** by this practical. You provide its name and resource group.
- The deployment operator needs permission to write a secret to the existing vault.
- You stated that Key Vault permissions for the VM identity will already be configured. The VM's system-assigned identity is created during deployment, so pre-granting access to that *new principal* is not possible unless your process pre-creates/updates the role assignment after the identity exists. This practical therefore assumes your organization has a process that grants the VM identity the **Key Vault Secrets User** role (or equivalent secret-read permission) on the vault. The script does not create a role assignment.
- The generated password is placed in Key Vault by `generator.sh` and passed securely to the deployment as a secure Bicep parameter. It is not printed. The script creates a temporary parameter file with restrictive permissions and removes it on exit.
- Password-based SSH is enabled only for this lab because the requested demo is to use the generated username/password through the Bastion portal. For production, prefer SSH keys or Microsoft Entra SSH login and disable password authentication.
- Bastion is deployed in `AzureBastionSubnet` (`/26`) and the VM has only a private IP. The VM has a system-assigned identity.
- Bastion login and managed-identity secret retrieval are separate demonstrations: Bastion provides the administrative connection; the VM identity provides access to Key Vault from inside the VM.

## Architecture

Operator workstation → Azure Bastion (public IP) → private Ubuntu VM  
Private Ubuntu VM (system-assigned managed identity) → existing Key Vault secret

## Prerequisites

1. Azure CLI and Bicep installed; Bash available.
2. Existing resource group for the lab VM/network/Bastion.
3. Existing Key Vault name and resource group.
4. Operator identity has `secrets/set` permission on the vault (for example, Key Vault Secrets Officer under the RBAC model).
5. After VM creation, grant its managed identity Key Vault Secrets User on the vault, or ensure an automated identity-governance process does so. Wait for role assignment propagation.

## 1. Run the generator

```bash
chmod +x generator.sh
./generator.sh
```

The script prompts for the lab resource group and existing vault details. It creates a random username and password, writes the password into Key Vault, then deploys the network, Bastion and VM. It prints the generated username and secret name at the end; retrieve the password from the vault when you need it:

```bash
az keyvault secret show \
  --vault-name "<KEY_VAULT_NAME>" \
  --name "<SECRET_NAME>" \
  --query value -o tsv
```

Avoid copying the password into shared terminals, recordings, or lecture slides.

## 2. Grant/read-check the VM identity

After deployment, obtain the principal ID:

```bash
VM_ID=$(az vm show -g "<LAB_RESOURCE_GROUP>" -n "vm-bicep-kv-bastion" --query id -o tsv)
PRINCIPAL_ID=$(az vm show -g "<LAB_RESOURCE_GROUP>" -n "vm-bicep-kv-bastion" --query identity.principalId -o tsv)
echo "$PRINCIPAL_ID"
```

If permissions are already configured by your administrator, skip role assignment. If they are not, an authorized administrator can grant the minimum read role (this command is shown for teaching only):

```bash
VAULT_ID=$(az keyvault show -g "<VAULT_RESOURCE_GROUP>" -n "<KEY_VAULT_NAME>" --query id -o tsv)
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$VAULT_ID"
```

This is a separate post-deployment step because the VM's system-assigned principal ID does not exist until the VM is created. If the vault uses legacy access policies rather than Azure RBAC, configure the equivalent `get` secret permission instead.

## 3. Connect through Azure Bastion

In Azure Portal:
1. Open the VM `vm-bicep-kv-bastion`.
2. Select **Connect → Bastion**.
3. Use the generated administrator username and the password stored in Key Vault.
4. Connect. The VM does not have a public IP.

The Bastion resource may take several minutes to provision. Bastion usage is billable.

## 4. Retrieve the secret from inside the VM using managed identity

Inside the VM, Azure CLI is installed by cloud-init. Run:

```bash
az login --identity
az keyvault secret show \
  --vault-name "<KEY_VAULT_NAME>" \
  --name "<SECRET_NAME>" \
  --query value -o tsv
```

If this returns `Forbidden`, verify that the VM identity has secret-read permission on the vault, that the vault's authorization model matches the configured permission, and allow time for role propagation. Also check Key Vault networking/firewall rules.

## 5. Verify network and identity

From your workstation:

```bash
az vm show -g "<LAB_RESOURCE_GROUP>" -n vm-bicep-kv-bastion \
  --query "{identity:identity,publicIP:publicIps,privateIP:privateIps}" -o json
az network bastion show -g "<LAB_RESOURCE_GROUP>" -n bastion-bicep-lab \
  --query "{name:name,state:provisioningState,sku:sku.name}" -o json
```

## Cleanup

Delete only the dedicated lab resource group. Do not delete the existing Key Vault:

```bash
az group delete --name "<LAB_RESOURCE_GROUP>" --yes --no-wait
```
