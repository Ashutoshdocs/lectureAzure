# Module 05 – Create and Manage an Azure Storage Account

## Objective
Create a storage account, inspect it, create a blob container, and understand naming rules.

Prerequisite: a resource group exists.

Bash:
```bash
RG="rg-azcli-training"
LOCATION="centralindia"
STORAGE="stazcli$(openssl rand -hex 4)"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$LOCATION = "centralindia"
$STORAGE = "stazcli$((New-Guid).ToString('N').Substring(0,8))"
```

Storage account names must be globally unique, lowercase letters/numbers, and 3–24 characters.

## 1. Create a storage account
```bash
az storage account create \
  --name "$STORAGE" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2
```

PowerShell can run the same command on one line:
```powershell
az storage account create --name $STORAGE --resource-group $RG --location $LOCATION --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2
```

## 2. Verify
```bash
az storage account list --resource-group "$RG" --output table
az storage account show --name "$STORAGE" --resource-group "$RG" --output table
```

## 3. Create a blob container
For an authenticated lab user with suitable data-plane permissions, use login authentication:

```bash
az storage container create \
  --name "training-data" \
  --account-name "$STORAGE" \
  --auth-mode login
```

If authorization fails, assign the appropriate data-plane role (for example, Storage Blob Data Contributor) at the storage account or container scope and allow time for role propagation.

## 4. List containers
```bash
az storage container list --account-name "$STORAGE" --auth-mode login --output table
```

## 5. Optional: upload a file
```bash
echo "Azure CLI storage lab" > sample.txt
az storage blob upload --account-name "$STORAGE" --container-name "training-data" --name "sample.txt" --file "sample.txt" --auth-mode login
```

## Teaching points
- The control plane creates/configures the storage account.
- Blob containers and blobs are data-plane resources.
- Azure RBAC management permissions and blob data permissions are different.
- Prefer Entra ID login (`--auth-mode login`) over account keys for learning and secure operations.
