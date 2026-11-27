# Practical 3 – Bicep reruns, deleted resources and removed resource declarations

## Learning objectives

Use a Storage Account and Blob containers to understand Azure Resource Manager's default **Incremental** deployment behaviour.

Students will test three different situations:

1. Deploy a Storage Account and containers.
2. Delete a container in Azure Portal/CLI, then rerun the same Bicep file.
3. Remove a container resource declaration from Bicep, then rerun the file.

## Key concept

Bicep is declarative. A normal resource-group deployment uses **Incremental** mode by default.

- If a resource declared in the template is missing, rerunning the template creates it again.
- If a resource is removed from the template, Incremental mode does **not** delete that existing resource.
- Incremental mode applies the declared desired configuration; it does not mean “delete everything not declared”.

Complete mode has broader deletion semantics and can remove resources in the target resource group that are not in the template. It is potentially destructive, has scope-wide consequences, and is not needed for this beginner lab. For modern lifecycle management, Azure Deployment Stacks can also be taught separately.

## Files

- `main.bicep` – initial template with Storage Account and two containers.
- `main-container-removed.bicep` – same Storage Account but only one container declaration.
- `main-container-deleted.bicep` – same Storage Account with both containers declared; use this after manually deleting one container.
- `parameters.example.json` – sample parameters.

## 1. Create a dedicated resource group

```bash
az login
RG="rg-bicep-storage-behaviour"
az group create --name "$RG" --location centralus
```

Storage Account names must be globally unique, 3–24 lowercase letters/numbers. Set a unique name:

```bash
STG="stgbicep$(openssl rand -hex 4)"
echo "$STG"
```

## 2. Deploy initial template

```bash
az deployment group what-if -g "$RG" -f main.bicep \
  -p storageAccountName="$STG"

az deployment group create -g "$RG" -f main.bicep \
  -p storageAccountName="$STG"
```

Verify:

```bash
az storage account show -g "$RG" -n "$STG" -o table
az storage container list --account-name "$STG" --auth-mode login -o table
```

The deploying identity needs data-plane permissions such as **Storage Blob Data Contributor** to list containers using `--auth-mode login`. If that is not available, verify containers in the Portal or use an authorized account key for the lab.

## 3. Experiment A – Delete a container, then rerun Bicep

Delete `images` manually:

```bash
az storage container delete --account-name "$STG" --name images --auth-mode login
az storage container list --account-name "$STG" --auth-mode login -o table
```

Now rerun the original template:

```bash
az deployment group create -g "$RG" -f main.bicep \
  -p storageAccountName="$STG"
```

Verify that `images` is created again. Why? The template still declares the container, and Incremental deployment ensures that declared resource exists.

## 4. Experiment B – Remove a resource block, then rerun Bicep

Inspect `main-container-removed.bicep`. It declares the Storage Account and only the `logs` container. It does not declare `images`.

Deploy it:

```bash
az deployment group what-if -g "$RG" -f main-container-removed.bicep \
  -p storageAccountName="$STG"

az deployment group create -g "$RG" -f main-container-removed.bicep \
  -p storageAccountName="$STG"
```

List the containers:

```bash
az storage container list --account-name "$STG" --auth-mode login -o table
```

Expected result: `images` remains. Removing a resource block from a Bicep file does not delete that Azure resource in the default Incremental mode.

## 5. Optional discussion – What about Complete mode?

Complete mode is a resource-group-level deployment mode, not a safe “delete the one block I removed” mechanism. It can delete other resources in the resource group that are not represented by the template. Never run Complete mode in a shared or production resource group for this demo.

Use a disposable resource group and a carefully reviewed template if demonstrating Complete mode. Prefer a dedicated resource group containing only the resources intentionally managed by that template. Run `what-if` and inspect every deletion before proceeding. Azure Deployment Stacks offer explicit management of resources and deletion settings and are a better follow-on topic.

## 6. Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```

This deletes the lab Storage Account and containers. Do not use a shared Storage Account for this experiment.
