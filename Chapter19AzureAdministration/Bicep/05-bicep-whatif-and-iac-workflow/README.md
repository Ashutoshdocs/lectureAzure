# Practical 5 – Bicep What-If and the Infrastructure-as-Code workflow

## Goal

Learn the normal Bicep/ARM Infrastructure-as-Code (IaC) command lifecycle and understand what Azure does when you build, validate, preview, deploy, inspect, update and delete infrastructure.

This practical uses a **Storage Account and Blob containers** so students can focus on deployment behaviour without VM costs.

## Bicep command lifecycle

| Stage | Command | Purpose |
|---|---|---|
| Build | `az bicep build` | Compile `.bicep` into ARM JSON |
| Decompile (optional) | `az bicep decompile` | Convert supported ARM JSON into Bicep |
| Lint | `az bicep lint` | Check style and common issues |
| Validate | `az deployment group validate` | Ask Azure to validate the deployment |
| Preview | `az deployment group what-if` | Predict creates, changes and deletes |
| Deploy | `az deployment group create` | Apply the declared configuration |
| Inspect | `az deployment group show` | Inspect a deployment record |
| List history | `az deployment group list` | Review previous deployments |
| Delete | `az group delete` or resource-specific delete | Remove deployed resources |

> `what-if` is a preview, not a deployment and not a guarantee that every runtime issue will be detected. It does not change resources.

## Prerequisites

- Azure CLI with Bicep support.
- Logged-in identity with permission to deploy resources in a dedicated resource group.
- Bash shell.
- A unique Storage Account name (3–24 lowercase letters/numbers).

## 1. Create a lab resource group

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"

RG="rg-bicep-iac-workflow"
LOCATION="centralus"
STG="stgiac$(openssl rand -hex 4)"

az group create --name "$RG" --location "$LOCATION"
echo "Storage Account: $STG"
```

## 2. Build and lint

```bash
az bicep version
az bicep build --file main.bicep
az bicep lint --file main.bicep
```

- Build checks that Bicep can compile and creates `main.json` beside the Bicep file.
- Lint reports recommended improvements. Some lint messages are warnings, not deployment blockers.
- The generated ARM JSON is an output artifact; normally edit the `.bicep` source, not the generated JSON.

## 3. Validate

```bash
az deployment group validate \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Validation checks the template against Azure's deployment validation path. It does not create the resources.

## 4. What-if – before first deployment

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Expected: the Storage Account and containers are shown as resources to be created (`+` / `Create`, depending on CLI output formatting).

Discuss:
- What resources will be created?
- Which properties are being configured?
- Why is this safer than immediately deploying?

## 5. Deploy

```bash
az deployment group create \
  --name iac-first-deployment \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Verify:

```bash
az storage account show --resource-group "$RG" --name "$STG" --output table
az resource list --resource-group "$RG" --output table
```

## 6. Run what-if again without changing the template

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Expected: no meaningful changes (`NoChange`), because deployed state matches the template.

## 7. Change a property and preview the update

Open `main.bicep` and change:

```bicep
accessTier: 'Hot'
```

to:

```bicep
accessTier: 'Cool'
```

Now run:

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Expected: What-if reports a modification to the Storage Account property. Apply the update only after reviewing:

```bash
az deployment group create \
  --name iac-change-access-tier \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters storageAccountName="$STG" location="$LOCATION"
```

Then change the tier back to `Hot`, preview, and deploy if you want to leave the lab in its original state.

## 8. Rename a resource – understand replacement

Change the Storage Account name parameter to a different globally unique name and run What-if.

Important: Azure Storage Account names are part of the resource identity and cannot be renamed in place. What-if may show a new account to create, but it does not automatically migrate data from the old account. Treat resource-name changes as a migration/replacement exercise.

## 9. Inspect deployment history

```bash
az deployment group list \
  --resource-group "$RG" \
  --query "[].{name:name,state:properties.provisioningState,timestamp:properties.timestamp}" \
  --output table

az deployment group show \
  --resource-group "$RG" \
  --name iac-first-deployment \
  --query "{state:properties.provisioningState,correlationId:properties.correlationId,outputs:properties.outputs}" \
  --output json
```

Deployment history records the deployment operation and template/parameter metadata. Do not put secrets in plain-text parameters or source files.

## 10. Understand idempotency

Run the same `az deployment group create` command again.

Expected: ARM evaluates the declared desired configuration and leaves matching resources in place. A repeated deployment should converge on the same declared state rather than create duplicate Storage Accounts. This is the practical meaning of idempotent IaC deployment.

It is not the same as “Bicep constantly monitors Azure.” Bicep is a declarative template; a deployment happens only when you submit it. For drift detection, run What-if or use governance/automation tools on a schedule.

## 11. Delete resources safely

For this lab, the simplest cleanup is to delete the dedicated resource group:

```bash
az group delete --name "$RG" --yes --no-wait
```

Do not use this command against a shared resource group. Confirm the resource group contains only lab resources before deleting it.

## Instructor recap

1. **Build** – compile Bicep.
2. **Lint** – check style and common problems.
3. **Validate** – validate the proposed deployment.
4. **What-if** – preview changes without applying them.
5. **Create** – apply the deployment.
6. **Show/list** – inspect deployment history.
7. **Repeat** – demonstrate idempotent convergence.
8. **Cleanup** – remove lab resources deliberately.

## What-if limitations and safe practice

- What-if predicts changes based on the current Azure state and the template; provider-side defaults or runtime behaviour can make the final result differ.
- Review `Modify`, `Create`, `Delete`, `NoChange`, and any `Ignore`/`Unsupported` output carefully.
- Large templates can produce noisy output. Use `--result-format FullResourcePayloads` when you need detailed property-level output, or `--result-format ResourceIdOnly` for a concise list.
- What-if requires read permissions for resources being evaluated as well as deployment permissions.
- Always target a dedicated resource group for classroom destructive experiments.
