# Module 15 – Verify and Clean Up Azure CLI Lab Resources

## Objective
Inspect resources, estimate what will be removed, and delete the dedicated lab resource group.

## 1. List resource groups
```bash
az group list --output table
```

## 2. List resources in the lab group
```bash
az resource list --resource-group "rg-azcli-training" --output table
```

For the end-to-end project:
```bash
az resource list --resource-group "rg-azcli-project" --output table
```

## 3. Confirm the exact target
```bash
az group show --name "rg-azcli-training" --output json
```

## 4. Delete only the dedicated lab resource group
```bash
az group delete --name "rg-azcli-training" --yes
```

For the separate end-to-end project group:
```bash
az group delete --name "rg-azcli-project" --yes
```

## 5. Verify deletion
```bash
az group exists --name "rg-azcli-training"
az group exists --name "rg-azcli-project"
```

Expected result after deletion: `false`.

## Important
- Do not run cleanup against a production resource group.
- Resource group deletion is destructive and removes all resources in that group.
- Resources created outside the lab resource group (for example, a separately created service principal or user-assigned identity) may need separate cleanup.
- Disks, snapshots, public IPs, and other resources deliberately created in another resource group are not deleted with this group.

## Lab task
Before deleting, export a resource inventory:
```bash
az resource list --resource-group "rg-azcli-training" --output json > lab-resource-inventory.json
```
Discuss which resources are deleted with the group and which external identities or resources need independent cleanup.
