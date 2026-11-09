# Module 04 – Create and Manage Resource Groups

## Objective
Create a resource group, inspect it, apply tags, and delete it.

Set variables first.

Bash:
```bash
LOCATION="centralindia"
RG="rg-azcli-training"
```

PowerShell:
```powershell
$LOCATION = "centralindia"
$RG = "rg-azcli-training"
```

## 1. Create
```bash
az group create --name "$RG" --location "$LOCATION" --tags Environment=Training Owner=Student
```

PowerShell:
```powershell
az group create --name $RG --location $LOCATION --tags Environment=Training Owner=Student
```

## 2. List and show
```bash
az group list --output table
az group show --name "$RG" --output json
```

## 3. Update tags
```bash
az group update --name "$RG" --set tags.Project=AzureCLI
```

## 4. Delete (destructive)
```bash
az group delete --name "$RG" --yes --no-wait
```

Check deletion:
```bash
az group exists --name "$RG"
```

## Teaching points
- A resource group is a logical management container, not a physical network boundary.
- Resources in a resource group can be in different regions, subject to service rules.
- Deleting a resource group deletes its contained resources.
- Tags help organize cost, ownership, and environment.

## Lab task
Create `rg-dev`, `rg-test`, and `rg-prod` in a region of your choice. Add an `Environment` tag to each. List them and delete only `rg-test`.
