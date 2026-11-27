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
- `README.md` — portal/CLI teaching steps and comparison.

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

If you use PowerShell, set the same variables with `$LOCATION = "centralindia"` etc. The commands below use Bash syntax for compactness.

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

**Expected teaching result:** both Storage Accounts still exist. The normal resource-group Bicep deployment uses incremental mode by default. Resources omitted from a later incremental deployment are not automatically deleted. The deployment updates/manages resources represented by the new template; it does not treat omission as a delete instruction.

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

The `--action-on-unmanage delete` setting is important. It tells the stack what to do with resources that were previously managed by the stack but are no longer present in its updated template. Do not rely on an implicit default for this teaching exercise.

## Part 5 — Deployment Stack: remove Storage Account 2 and update the stack

1. Make a backup copy of `storage-stack.bicep`.
2. Edit `storage-stack.bicep`.
3. Remove all three declarations for Storage Account 2:
   - `storageAccount2`
   - `blobService2`
   - `container2`
4. Keep Storage Account 1 and its child resources.
5. Run what-if for the stack update:

```bash
az stack group what-if \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --template-file storage-stack.bicep \
  --parameters storageAccountName1="$STACK_SA1" storageAccountName2="$STACK_SA2" location="$LOCATION" \
  --action-on-unmanage delete \
  --deny-settings-mode none
```

6. Review the proposed changes carefully. Confirm that the second Storage Account and its child resources are identified for deletion/unmanagement according to the stack action.
7. Apply the update:

```bash
az stack group create \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --template-file storage-stack.bicep \
  --parameters storageAccountName1="$STACK_SA1" storageAccountName2="$STACK_SA2" location="$LOCATION" \
  --action-on-unmanage delete \
  --deny-settings-mode none
```

Verify:

```bash
az storage account list --resource-group "$RG_STACK" \
  --query "[].name" -o table
```

**Expected teaching result:** only Storage Account 1 remains in the stack resource group's managed deployment. Storage Account 2 is deleted because the stack was updated with `--action-on-unmanage delete`.

## Part 6 — Compare the results with students

| Experiment | What changed in the file? | Deployment operation | Expected result for Storage Account 2 |
|---|---|---|---|
| Normal Bicep | Removed account 2 and its child declarations | `az deployment group create` (incremental) | Remains in Azure |
| Deployment Stack | Removed account 2 and its child declarations | `az stack group create` with `--action-on-unmanage delete` | Deleted by stack update |

### Core concept

- **Normal Bicep deployment:** Bicep is the language used to describe resources. A standard resource-group deployment is incremental by default. Omission from the next template does not delete an existing resource.
- **Deployment Stack:** a lifecycle-management feature that tracks the resources managed by the stack. Its action-on-unmanage setting determines what happens when a resource is removed from the stack's template. With `delete`, removed managed resources are deleted during the stack update.

A Deployment Stack is not simply a different Bicep syntax. The same Bicep language can be used with a normal deployment or as the template for a stack; the deployment mechanism and lifecycle behavior are different.

## Important safety notes

- This lab intentionally demonstrates deletion. Use only the dedicated demo resource groups.
- Read the stack what-if output before applying the update.
- `--action-on-unmanage delete` can delete resources that were previously managed by the stack and are now omitted from its template.
- The child Blob service and container declarations are removed along with Storage Account 2. Deleting a Storage Account deletes its contained data.
- Do not run the stack update against a production resource group.
- This exercise uses `--deny-settings-mode none` so deny settings do not block the lab's intended operations. Do not copy that choice into a production design without reviewing your governance requirements.

## Cleanup

After teaching, remove the stack first, then the two resource groups:

```bash
az stack group delete \
  --name "storage-lifecycle-stack" \
  --resource-group "$RG_STACK" \
  --action-on-unmanage delete \
  --yes

az group delete --name "$RG_BICEP" --yes --no-wait
az group delete --name "$RG_STACK" --yes --no-wait
```

The stack delete command uses `--action-on-unmanage delete` to delete resources still managed by the stack. Confirm the target stack and resource group before running it.

## Troubleshooting

- **Storage account name already taken:** choose a different globally unique name.
- **Invalid storage account name:** use only lowercase letters and numbers, 3–24 characters.
- **Authorization failure:** verify that your identity has resource deployment permissions; for container listing, also verify Blob data-plane permissions.
- **Stack command unavailable:** update Azure CLI and check `az stack group --help`.
- **What-if proposes unexpected deletions:** stop and inspect the template, stack name, resource group, and action-on-unmanage setting before applying.

## Expected final outcome

- Normal Bicep experiment: both accounts remain after removing account 2 from the template and redeploying incrementally.
- Deployment Stack experiment: account 2 is deleted after removing it from the stack template and updating with `--action-on-unmanage delete`.
