# Azure Storage Upload: Access Key vs Connection String

This guide shows two ways to authenticate the Azure CLI when you upload a file to Azure Blob Storage:

1. **Access Key**: you pass the storage account name and key on every command.
2. **Connection String**: one string holds everything, set once as an environment variable.

## Prerequisites

- An Azure subscription with a storage account and a container
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed, or Azure Cloud Shell (Bash)
- Signed in with `az login`

| Resource | Name used in examples |
|---|---|
| Storage Account | `mystorageblaze123` |
| Container | `demo-container` |

> Replace `<resource-group>`, `<account-key>` and `<connection-string>` with your own values. Never commit real keys to source control.

---

## Method 1: Using an Access Key

### Step 1: Get the Access Key
Find it in the portal under **Storage Account → Security + networking → Access keys**, or with the CLI:

```bash
az storage account keys list \
  --account-name mystorageblaze123 \
  --resource-group <resource-group> \
  --query "[0].value" -o tsv
```

### Step 2: Create a File Locally
This is the file you'll upload to Blob Storage.

```bash
echo "Hello from Access Key" > file1.txt
```

### Step 3: Upload the File with Account Name + Access Key
You pass the account name and key explicitly on the command.

```bash
az storage blob upload \
  --account-name mystorageblaze123 \
  --account-key <account-key> \
  --container-name demo-container \
  --name file1.txt \
  --file file1.txt
```

---

## Method 2: Using a Connection String

### Step 1: Get the Connection String
Find it in the portal under **Storage Account → Security + networking → Access keys → Connection string**, or with the CLI:

```bash
az storage account show-connection-string \
  --name mystorageblaze123 \
  --resource-group <resource-group> \
  -o tsv
```

It looks like this:

```
DefaultEndpointsProtocol=https;AccountName=mystorageblaze123;AccountKey=<account-key>;EndpointSuffix=core.windows.net
```

### Step 2: Set the Connection String as an Environment Variable
The Azure CLI reads `AZURE_STORAGE_CONNECTION_STRING` automatically. It holds the account name, key and endpoints in one value.

```bash
export AZURE_STORAGE_CONNECTION_STRING="<connection-string>"
```

### Step 3: Create Another File Locally

```bash
echo "Hello from Connection String" > file2.txt
```

### Step 4: Upload the File
No `--account-name` or `--account-key` needed; the CLI picks them up from the environment variable.

```bash
az storage blob upload \
  --container-name demo-container \
  --name file2.txt \
  --file file2.txt
```

> You can also pass it directly with `--connection-string "<connection-string>"` instead of setting the variable.

---

## Verify the Uploads

List the blobs in the container to confirm both files arrived:

```bash
az storage blob list \
  --container-name demo-container \
  --query "[].name" -o table
```

**Expected output:**
```
Result
---------
file1.txt
file2.txt
```

---

## Key Differences

| | Access Key | Connection String |
|---|---|---|
| **What you provide** | Account name + key, separately | One string with name, key and endpoints |
| **Configuration** | More manual; repeated on every command | Set once, reused by every command |
| **Best for** | Quick one-off CLI commands | Applications, config files and automation |

## Security Notes

- Both methods contain the **account key**, which gives full access to the entire storage account.
- Both are less secure than **Managed Identity** or **Microsoft Entra ID** (`--auth-mode login`).
- Don't hardcode keys or connection strings in application code or scripts; store them in **Azure Key Vault** or environment variables.
- Rotate access keys regularly (Storage Account → Access keys → **Rotate key**).
