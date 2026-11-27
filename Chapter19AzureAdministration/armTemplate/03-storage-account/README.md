# Practical 3 – Create a Storage Account and Blob Containers using ARM

## Learning objectives

- Deploy a StorageV2 account using ARM JSON.
- Configure access tier, TLS and public access settings.
- Create Blob containers as child resources.
- Understand parent/child resource names.

## 1. Create resource group

```bash
az login
RG="rg-arm-storage"
az group create --name "$RG" --location centralindia
```

## 2. Choose a unique Storage Account name

Storage Account names must be globally unique, lowercase, 3–24 characters.

```bash
STG="starm$RANDOM$RANDOM"
```

## 3. Validate and preview

```bash
az deployment group validate \
  --resource-group "$RG" \
  --template-file storage-template.json \
  --parameters storageAccountName="$STG"

az deployment group what-if \
  --resource-group "$RG" \
  --template-file storage-template.json \
  --parameters storageAccountName="$STG"
```

## 4. Deploy

```bash
az deployment group create \
  --name arm-storage-deployment \
  --resource-group "$RG" \
  --template-file storage-template.json \
  --parameters storageAccountName="$STG"
```

## 5. Verify

```bash
az storage account show -g "$RG" -n "$STG" -o table
az resource list -g "$RG" -o table
```

To list containers using Microsoft Entra authorization, the signed-in user needs a data role such as Storage Blob Data Contributor:

```bash
az storage container list --account-name "$STG" --auth-mode login -o table
```

## Teaching discussion

- What does `StorageV2` mean?
- Why is public blob access disabled?
- Why do child resource names include the Storage Account and Blob service?
- What is the difference between management-plane and data-plane permissions?

## Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```
