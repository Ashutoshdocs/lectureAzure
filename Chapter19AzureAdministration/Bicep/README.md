# Azure Bicep – Hands-on Lecture Practicals

This package contains four independent, instructor-led Azure Bicep practicals.
All deployments target **Central US** unless a parameter overrides the location.

## Folder map

1. `01-vm-components-individually/` – build a Linux VM from separate Bicep components/modules.
2. `02-vm-keyvault-bastion-managed-identity/` – generate VM credentials, save the password in an existing Key Vault, deploy a private Linux VM and Azure Bastion, then retrieve the secret from the VM using its managed identity.
3. `03-bicep-storage-incremental-behaviour/` – use a Storage Account and Blob containers to demonstrate what happens when resources are deleted or removed from a Bicep file.
4. `04-bicep-cloud-init/` – provision a Linux VM and configure it at first boot with cloud-init.

## Common prerequisites

- Azure subscription and a resource group in which you can deploy.
- Azure CLI (`az`) logged in with `az login`.
- Bicep CLI available through Azure CLI (`az bicep install` if needed).
- Bash shell (Azure Cloud Shell Bash, Linux, or WSL) for the shell scripts.
- Sufficient permissions to create the resources in the selected resource group.
- For Practical 2: an **existing Key Vault**, its resource group, and an already configured permission for the VM's system-assigned managed identity to read secrets. The deployment identity must also be allowed to set a secret in that vault.

## General workflow

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az group create --name "<RESOURCE_GROUP>" --location centralus
cd <PRACTICAL_FOLDER>
az deployment group what-if --resource-group "<RESOURCE_GROUP>" --template-file main.bicep
az deployment group create --resource-group "<RESOURCE_GROUP>" --template-file main.bicep
```

Read the README inside each practical before deploying. Resource names must be globally unique where Azure requires it (for example, Storage Account names and public IP DNS labels).

## Cost and cleanup

VMs, public IPs, Bastion, and Storage Accounts can incur charges. Bastion can be a significant ongoing cost. Delete the practical resource group after the lecture only if it contains no shared resources:

```bash
az group delete --name "<RESOURCE_GROUP>" --yes --no-wait
```

Do **not** delete a resource group that contains a pre-existing Key Vault or other shared infrastructure. For Practical 2, the Key Vault is expected to be pre-existing and should remain untouched.

5. `05-bicep-whatif-and-iac-workflow/` – Bicep build, lint, validate, what-if, deploy, inspect history, idempotency and safe cleanup using a Storage Account.
