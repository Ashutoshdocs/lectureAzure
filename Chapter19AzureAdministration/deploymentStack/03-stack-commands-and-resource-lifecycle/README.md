# Practical 3 – Important Deployment Stack commands and resource lifecycle

## Learning objectives

- Learn the most useful `az stack group` commands.
- Remove a resource declaration and observe detach vs delete behaviour.
- Understand stack deletion and managed resource deletion.
- Experiment with deny settings.
- Compare stack behaviour with ordinary Bicep Incremental deployments.

## Files

- `main.bicep` – Storage Account with two containers.
- `main-one-container.bicep` – same Storage Account with only the `logs` container declaration.
- `main-two-containers.bicep` – template that declares both containers (used to reset/recreate the lab state).
- `commands.sh` – command reference for stack create/show/list/what-if/delete.

## 0. Prepare a dedicated lab

```bash
az login
RG="rg-stack-lifecycle"
az group create --name "$RG" --location centralus
STG="ststack$(openssl rand -hex 4)"
echo "$STG"
```

Use a unique Storage Account name (3–24 lowercase letters/numbers).

## 1. Create a stack with two containers

```bash
SUB_ID=$(az account show --query id -o tsv)
STACK_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Resources/deploymentStacks/stack-lifecycle"
az stack-whatif group create \
  --name stack-lifecycle-preview \
  --resource-group "$RG" \
  --stack-id "$STACK_ID" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none \
  --retention-interval P5D

az stack group create \
  --name stack-lifecycle \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none
```

Verify the stack and resources:

```bash
az stack group show -n stack-lifecycle -g "$RG" -o json
az stack group list -g "$RG" -o table
az resource list -g "$RG" -o table
```

## 2. Remove a section (resource block) and run again – detachAll

The file `main-one-container.bicep` removes the `images` container resource declaration.

Preview:

```bash
az stack-whatif group create \
  --name stack-lifecycle-preview-remove-images \
  --resource-group "$RG" \
  --stack-id "$STACK_ID" \
  --template-file main-one-container.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none \
  --retention-interval P5D
```

Apply:

```bash
az stack group create \
  --name stack-lifecycle \
  --resource-group "$RG" \
  --template-file main-one-container.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none
```

Expected: the `images` container is no longer managed by this stack, but it remains in Azure. The stack still manages the Storage Account and `logs` container.

This is the key teaching distinction: **detach is not delete**.

## 3. Reset the stack to two containers

```bash
az stack group create \
  --name stack-lifecycle \
  --resource-group "$RG" \
  --template-file main-two-containers.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage detachAll \
  --deny-settings-mode none
```

Because the container still exists, the stack can include it in its managed set again.

## 4. Remove a section and delete the unmanaged resource

Only perform this experiment in the dedicated disposable resource group.

Preview:

```bash
az stack-whatif group create \
  --name stack-lifecycle-preview-delete-images \
  --resource-group "$RG" \
  --stack-id "$STACK_ID" \
  --template-file main-one-container.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage deleteResources \
  --deny-settings-mode none \
  --retention-interval P5D
```

Apply the update:

```bash
az stack group create \
  --name stack-lifecycle \
  --resource-group "$RG" \
  --template-file main-one-container.bicep \
  --parameters storageAccountName="$STG" \
  --action-on-unmanage deleteResources \
  --deny-settings-mode none
```

Expected: the removed `images` container is deleted as it becomes unmanaged under the selected action. Verify in the Portal or with Storage data-plane access.

**Warning:** `deleteResources` can delete resources removed from the stack template. It is powerful and should be used only when the stack is the authoritative owner of those resources and the deletion is intended.

## 5. Important stack commands

```bash
# Create or update a resource-group stack
az stack group create --name <STACK_NAME> -g <RESOURCE_GROUP> \
  -f <TEMPLATE_FILE> --action-on-unmanage detachAll

# Preview a stack deployment (stack must already exist)
az stack-whatif group create --name <PREVIEW_NAME> -g <RESOURCE_GROUP> \
  --stack-id <FULL_STACK_RESOURCE_ID> -f <TEMPLATE_FILE> \
  --action-on-unmanage detachAll --deny-settings-mode none --retention-interval P5D

# Show/list stored stack what-if results
az stack-whatif group show --name <PREVIEW_NAME> -g <RESOURCE_GROUP>
az stack-whatif group list -g <RESOURCE_GROUP>

# Show one stack
az stack group show --name <STACK_NAME> -g <RESOURCE_GROUP>

# List stacks in a resource group
az stack group list -g <RESOURCE_GROUP>

# Delete the stack object (check unmanage behaviour first)
az stack group delete --name <STACK_NAME> -g <RESOURCE_GROUP> --action-on-unmanage detachAll

# Help for all commands/options
az stack group --help
az stack group create --help
az stack group delete --help
```

A stack-specific preview is created with `az stack-whatif group create` (not `az stack group what-if`). The preview result can be read with `az stack-whatif group show` and listed with `az stack-whatif group list`. The preview command requires the fully qualified stack ID, a result name, action-on-unmanage, deny-settings mode, and a retention interval such as `P5D`.

Always check `--help` in the installed CLI version before teaching or running destructive commands.

## 6. Deny settings demonstration (optional)

Deny settings can be applied to resources managed by the stack. For a lab, create/update a stack with a mode such as:

```bash
--deny-settings-mode denyDelete
```

or:

```bash
--deny-settings-mode denyWriteAndDelete
```

You may optionally specify excluded principals or actions where supported by the CLI version. Do not guess these values: inspect `az stack group create --help` and the current Azure documentation.

After applying a deny setting, try a manual delete or write operation against a managed resource with a test identity. Observe the authorization result. Then update the stack to remove/relax the deny setting before cleanup.

Deny settings are enforced through deny assignments and can affect administrators and automation. Understand exclusions and privileged access behaviour before using them in production.

## 7. Delete the stack and clean up

First inspect the stack's current action-on-unmanage setting and managed resource list:

```bash
az stack group show -n stack-lifecycle -g "$RG" -o json
```

For this lab, you can delete the dedicated resource group after the exercise:

```bash
az group delete --name "$RG" --yes --no-wait
```

Deleting the whole dedicated resource group removes the stack and its contained resources. Do not run this against a shared resource group.

## Comparison recap

| Operation | Ordinary Bicep Incremental | Deployment Stack |
|---|---|---|
| Resource still declared but manually deleted | Next deployment recreates it | Next stack deployment can recreate it |
| Resource block removed | Existing resource normally remains | `detachAll` leaves it but removes stack management; `deleteResources` deletes it |
| Track managed resource set | No dedicated stack object | Stack tracks its managed resources |
| Deny settings | Not a feature of ordinary Bicep deployment | Stack supports deny settings |
| Preview | `az deployment group what-if` | `az stack-whatif group create` |

## Important command concept

`az stack group delete` deletes the **stack object**. What happens to the stack-managed resources depends on the selected unmanage action and command options supported by the installed CLI. Do not assume deleting a stack object always deletes all managed resources or always leaves them behind; inspect the action-on-unmanage setting and command help first.
