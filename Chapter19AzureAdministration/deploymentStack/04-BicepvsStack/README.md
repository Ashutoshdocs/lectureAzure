# Azure Bicep vs Deployment Stacks — Storage Account Lifecycle Practical

## Objective

This practical teaches the lifecycle difference between:

1. A normal Bicep resource-group deployment.
2. An Azure Deployment Stack created from a Bicep file.

You will create **two Storage Accounts**, each with **one private Blob container**. Then you will remove the second Storage Account definition from the Bicep file and deploy again. Finally, you will repeat the same experiment using an Azure Deployment Stack configured to delete resources that are removed from its template.

> Important: use two separate resource groups for the two experiments. This keeps the ordinary Bicep test and Deployment Stack test independent.

## Folder contents

- `storage-accounts.bicep` — ordinary Bicep deployment with two Storage Accounts and one container in each.
- `storage-stack.bicep` — same initial infrastructure, intended to be deployed as a Deployment Stack.
- `README.md` — step-by-step CLI practical and comparison.

## Architecture

```text
Resource group
|
+-- Storage Account 1
|   +-- Blob service (default)
|       +-- container-one (private)
|
+-- Storage Account 2
    +-- Blob service (default)
        +-- container-two (private)
```

Both Storage Accounts use:
- StorageV2
- Standard locally redundant storage (Standard_LRS)
- Hot access tier
- HTTPS-only traffic
- Minimum TLS 1.2
- Anonymous blob access disabled

## Prerequisites

- Azure subscription and permission to create resource groups, storage accounts, and deployment stacks.
- Azure CLI installed and signed in (`az login`).
- Bicep CLI available through Azure CLI (`az bicep version`).
- Two globally unique Storage Account names. Names must be 3–24 characters, lowercase letters and numbers only.

Choose unique names before starting. Example names below are placeholders; replace them with your own names:

```bash
export LOCATION="centralindia"
export RG_BICEP="rg-bicep-lifecycle-demo"
export RG_STACK="rg-stack-lifecycle-demo"

export SA1="stbicepdemoabc01"
export SA2="stbicepdemoabc02"
export STACK_SA1="ststackdemoabc01"
export STACK_SA2="ststackdemoabc02"
```

If you use PowerShell, set the same variables with `$LOCATION = "centralindia"` etc. The commands below use Bash syntax for compactness. Git Bash on Windows supports this syntax.

## Part 1 — Create the resource groups

```bash
az group create --name "$RG_BICEP" --location "$LOCATION"
az group create --name "$RG_STACK" --location "$LOCATION"
```

Check:

```bash
az group list --query "[?name=='$RG_BICEP' || name=='$RG_STACK'].{Name:name,Location:location}" -o table
```

## Part 2 — Normal Bicep deployment: create two Storage Accounts

1. Open `storage-accounts.bicep`.
2. Keep both Storage Account resource blocks and their child Blob service/container blocks.
3. Validate and deploy:

```bash
az bicep build --file storage-accounts.bicep

az deployment group what-if \
  --resource-group "$RG_BICEP" \
  --template-file storage-accounts.bicep \
  --parameters storageAccountName1="$SA1" storageAccountName2="$SA2" location="$LOCATION"

az deployment group create \
  --name "normal-bicep-initial" \
  --resource-group "$RG_BICEP" \
  --template-file storage-accounts.bicep \
  --parameters storageAccountName1="$SA1" storageAccountName2="$SA2" location="$LOCATION"
```

Verify both accounts and their containers:

```bash
az storage account list --resource-group "$RG_BICEP" \
  --query "[].{Name:name,Kind:kind,SKU:sku.name}" -o table

az storage container list --account-name "$SA1" --auth-mode login -o table
az storage container list --account-name "$SA2" --auth-mode login -o table
```

Your signed-in identity needs suitable data-plane permission (for example, Storage Blob Data Reader) to list containers with `--auth-mode login`. If you only want to verify resource creation, use the account list command or inspect the Storage Accounts in the portal.

## Part 3 — Normal Bicep: remove one Storage Account and deploy again

This is the key demonstration.

1. Make a backup copy of `storage-accounts.bicep`.
2. Edit `storage-accounts.bicep`.
3. Remove **all three resource declarations** for Storage Account 2:
   - `storageAccount2`
   - `blobService2`
   - `container2`
4. Keep Storage Account 1 and its Blob service/container unchanged.
5. Run the same deployment again, using the same resource group and parameters:

```bash
az deployment group what-if \
  --resource-group "$RG_BICEP" \
  --template-file storage-accounts.bicep \
  --parameters storageAccountName1="$SA1" storageAccountName2="$SA2" location="$LOCATION"

az deployment group create \
  --name "normal-bicep-after-removal" \
  --resource-group "$RG_BICEP" \
  --template-file storage-accounts.bicep \
  --parameters storageAccountName1="$SA1" storageAccountName2="$SA2" location="$LOCATION"
```

Now check the resource group again:

```bash
az storage account list --resource-group "$RG_BICEP" \
  --query "[].name" -o table
```

**Expected teaching result:** both Storage Accounts still exist. The normal resource-group Bicep deployment uses incremental mode by default. Resources omitted from a later incremental deployment are not automatically deleted. The deployment updates resources represented by the new template; it does not treat omission as a delete instruction.

Explain to learners: *“Removing a resource declaration from a normal Bicep file does not mean Azure deletes that existing resource.”*

## Part 4 — Deployment Stack: deploy the same two-account setup

Restore the original two-account content in `storage-stack.bicep` if you edited it. The supplied file already contains both accounts.

Create a Deployment Stack and explicitly configure deletion of resources that are no longer managed by the stack:

```bash
az stack group create \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --template-file storage-stack.bicep \
  --parameters storageAccountName1="$STACK_SA1" storageAccountName2="$STACK_SA2" location="$LOCATION" \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

Verify:

```bash
az storage account list --resource-group "$RG_STACK" \
  --query "[].name" -o table

az stack group show \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --query "{Name:name,ProvisioningState:provisioningState,ActionOnUnmanage:actionOnUnmanage}" -o yaml
```

`--action-on-unmanage deleteAll` tells the stack to delete resources that it previously managed but that are no longer present in the updated template. The accepted action values are `deleteAll`, `deleteResources`, and `detachAll`.

## Part 5 — Deployment Stack What-If: preview removal of Storage Account 2

**Important correction:** the command is **`az stack-whatif group create`**. It is not `az stack group what-if`.

### Step 5.1 — Edit the stack template

1. Make a backup copy of `storage-stack.bicep`.
2. Edit `storage-stack.bicep`.
3. Remove all three declarations for Storage Account 2:
   - `storageAccount2`
   - `blobService2`
   - `container2`
4. Keep Storage Account 1 and its child resources.
5. Save the file.

### Step 5.2 — Get the ID of the existing stack

The Stack What-If command needs the fully qualified ID of the existing Deployment Stack:

```bash
STACK_ID=$(az stack group show \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --query id -o tsv)

echo "$STACK_ID"
```

Confirm that the command prints a resource ID ending in:

```text
/providers/Microsoft.Resources/deploymentStacks/storage-lifecycle-stack
```

### Step 5.3 — Create a Stack What-If preview result

Use a separate name for the preview result. The preview name is not the name of the actual Deployment Stack.

```bash
az stack-whatif group create \
  --name "storage-lifecycle-stack-preview" \
  --resource-group "$RG_STACK" \
  --stack-id "$STACK_ID" \
  --template-file storage-stack.bicep \
  --parameters storageAccountName1="$STACK_SA1" storageAccountName2="$STACK_SA2" location="$LOCATION" \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none \
  --retention-interval P1D
```

### Step 5.4 — Display the preview

<<<<<<< HEAD
```bash
az stack-whatif group show \
  --name "storage-lifecycle-stack-preview" \
  --resource-group "$RG_STACK" \
  --with-property-changes true
```

Review the result. The preview should identify Storage Account 2 and its child resources as resources that will be removed according to the selected `deleteAll` action.

If you want to create another preview with the same name, delete the previous preview result first:

```bash
az stack-whatif group delete \
  --name "storage-lifecycle-stack-preview" \
  --resource-group "$RG_STACK" \
  --yes
```

**A What-If preview does not change the actual stack or delete resources.** It creates a preview result resource that you can inspect.

### Step 5.5 — Apply the stack update

Only after reviewing the preview, run the actual stack update:
=======
6. Review the proposed changes carefully. Confirm that the second Storage Account and its child resources are identified for deletion/unmanagement according to the stack action.
7. Apply the update:
>>>>>>> 70cc1243c466aa69327aa4779d5a58654c97260e

```bash
az stack group create \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --template-file storage-stack.bicep \
  --parameters storageAccountName1="$STACK_SA1" storageAccountName2="$STACK_SA2" location="$LOCATION" \
  --action-on-unmanage deleteAll \
  --deny-settings-mode none
```

Verify:

```bash
az storage account list --resource-group "$RG_STACK" \
  --query "[].name" -o table
```

**Expected teaching result:** only Storage Account 1 remains. Storage Account 2 is deleted because the updated stack no longer manages it and the stack uses `--action-on-unmanage deleteAll`.

## Part 6 — Compare the results with students

| Experiment | What changed in the file? | Deployment operation | Expected result for Storage Account 2 |
|---|---|---|---|
| Normal Bicep | Removed account 2 and its child declarations | `az deployment group create` (incremental) | Remains in Azure |
| Deployment Stack | Removed account 2 and its child declarations | `az stack group create` with `--action-on-unmanage deleteAll` | Deleted by stack update |

### Core concept

- **Normal Bicep deployment:** Bicep is the language used to describe resources. A standard resource-group deployment is incremental by default. Omission from the next template does not delete an existing resource.
- **Deployment Stack:** a lifecycle-management feature that tracks the resources managed by the stack. Its action-on-unmanage setting determines what happens when a resource is removed from the stack's template. With `deleteAll`, resources that are no longer managed are deleted during the stack update.
- **Deployment Stack What-If:** a separate preview operation. It creates a What-If result that can be inspected before the real stack update.

A Deployment Stack is not simply a different Bicep syntax. The same Bicep language can be used with a normal deployment or as the template for a stack; the deployment mechanism and lifecycle behavior are different.

## Important safety notes

- This lab intentionally demonstrates deletion. Use only the dedicated demo resource groups.
- Read the Stack What-If output before applying the update.
- `--action-on-unmanage deleteAll` can delete resources that were previously managed by the stack and are now omitted from its template.
- The child Blob service and container declarations are removed along with Storage Account 2. Deleting a Storage Account deletes its contained data.
- Do not run the stack update against a production resource group.
- This exercise uses `--deny-settings-mode none` so deny settings do not block the lab's intended operations. Do not copy that choice into a production design without reviewing your governance requirements.

## Cleanup

After teaching, remove the preview result, then remove the stack and the two resource groups:

```bash
az stack-whatif group delete \
  --name "storage-lifecycle-stack-preview" \
  --resource-group "$RG_STACK" \
  --yes

az stack group delete \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --action-on-unmanage deleteAll \
  --yes

az group delete --name "$RG_BICEP" --yes --no-wait
az group delete --name "$RG_STACK" --yes --no-wait
```

The stack delete command uses `--action-on-unmanage deleteAll` to delete resources still managed by the stack. Confirm the target stack and resource group before running it.

## Troubleshooting

- **`what-if` is not recognized under `az stack group`:** use `az stack-whatif group create`. The command groups are separate.
- **`az stack-whatif` is not recognized at all:** update Azure CLI with `az upgrade`, open a new terminal, then check `az stack-whatif group --help`.
- **Storage account name already taken:** choose a different globally unique name.
- **Invalid storage account name:** use only lowercase letters and numbers, 3–24 characters.
- **Authorization failure:** verify that your identity has resource deployment permissions; for container listing, also verify Blob data-plane permissions.
- **What-If proposes unexpected deletions:** stop and inspect the template, stack ID, stack name, resource group, and action-on-unmanage setting before applying.

## Expected final outcome

- Normal Bicep experiment: both accounts remain after removing account 2 from the template and redeploying incrementally.
- Deployment Stack experiment: Stack What-If previews removal; the subsequent stack update deletes account 2 because the stack uses `--action-on-unmanage deleteAll`.

## Microsoft documentation

- [Azure CLI — az stack-whatif group](https://learn.microsoft.com/cli/azure/stack-whatif/group)
- [Azure CLI — az stack group](https://learn.microsoft.com/cli/azure/stack/group)
