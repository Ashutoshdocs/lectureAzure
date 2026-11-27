# Practical 1 – Create a Linux VM and Storage Account with an Azure Deployment Stack

## Learning objectives

- Write a Bicep template for a Linux VM and Storage Account.
- Deploy the template as a resource-group Deployment Stack.
- Inspect the stack and the resources it manages.
- Understand the stack's resource relationship and outputs.

## Architecture

A dedicated resource group in Central US contains:
- VNet and subnet
- Network Security Group with SSH restricted to the supplied source CIDR
- Public IP and NIC
- Ubuntu 24.04 Linux VM using SSH public-key authentication
- StorageV2 Storage Account

The stack is deployed at resource-group scope and manages the resources declared by `main.bicep`.

## 1. Set up

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"

RG="rg-stack-vm-storage"
az group create --name "$RG" --location centralus

ssh-keygen -t ed25519 -f ~/.ssh/stack_vm -N ""
```

## 2. Validate and preview

```bash
az deployment group validate \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/stack_vm.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32" \
               storageAccountName="<UNIQUE_STORAGE_NAME>"

STACK_ID=$(az stack group show --name stack-vm-storage --resource-group "$RG" --query id -o tsv 2>/dev/null || true)
if [ -z "$STACK_ID" ]; then
  SUB_ID=$(az account show --query id -o tsv)
  STACK_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Resources/deploymentStacks/stack-vm-storage"
fi
az stack-whatif group create \
  --name stack-vm-storage-preview \
  --resource-group "$RG" \
  --stack-id "$STACK_ID" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/stack_vm.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32" \
               storageAccountName="<UNIQUE_STORAGE_NAME>" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none \
  --retention-interval P5D
```

Replace the SSH source CIDR and globally unique Storage Account name. `detachAll` is chosen for this first practical so that removing a declaration in a later exercise does not automatically delete the resource.

## 3. Create the stack

```bash
az stack group create \
  --name stack-vm-storage \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/stack_vm.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32" \
               storageAccountName="<UNIQUE_STORAGE_NAME>" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none
```

This creates/updates the stack and deploys its template resources. `--deny-settings-mode none` is used for a beginner lab so that students can inspect resources without an added deny assignment. Later practicals demonstrate deny settings.

## 4. Inspect the stack

```bash
az stack group show \
  --name stack-vm-storage \
  --resource-group "$RG" \
  --output json

az stack group show \
  --name stack-vm-storage \
  --resource-group "$RG" \
  --query "{name:name,state:provisioningState,managedResources:resources}" \
  --output json

az stack group list --resource-group "$RG" --output table
```

Inspect resources:

```bash
az resource list --resource-group "$RG" --output table
```

## 5. Connect to the VM

```bash
VM_IP=$(az vm show -g "$RG" -n vm-stack-demo \
  --show-details --query publicIps -o tsv)
ssh -i ~/.ssh/stack_vm azureadmin@"$VM_IP"
```

## 6. Teaching questions

- What is the difference between a Bicep template and a Deployment Stack?
- Which resources are recorded as managed by this stack?
- What does `action-on-unmanage detachAll` mean?
- What changes if deny settings are enabled?
- Does the stack create a separate virtual network service? No; the stack is a management resource that tracks the resources deployed from the template.

## Cleanup

For a dedicated lab resource group, delete the stack first, then delete the group if needed:

```bash
az stack group delete \
  --name stack-vm-storage \
  --resource-group "$RG" \
  --yes

az group delete --name "$RG" --yes --no-wait
```

Check the stack delete command help before running in a shared environment. Deleting the stack and deleting its managed resources are distinct decisions; the configured unmanage behaviour matters.
