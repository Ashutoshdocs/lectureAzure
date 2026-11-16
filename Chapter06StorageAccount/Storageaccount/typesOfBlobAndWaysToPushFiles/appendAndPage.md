# Azure Storage Practical: Append Blob + Page Blob

A hands-on lab using the Azure CLI to create a storage account, work with **Append Blobs** (for logs) and **Page Blobs** (for disks), and check blob types.

## Prerequisites

- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed, or Azure Cloud Shell (Bash)
- Signed in with `az login`

> The commands use Bash syntax (`$(...)`, `echo`, `head`). Run them in Azure Cloud Shell, Linux, macOS or WSL.

## Lab Resources

| Resource | Name |
|---|---|
| Resource Group | `rg-storage-lab` |
| Location | `centralindia` |
| Storage Account | `mystgappenddemo123` |
| Container (Append Blob demo) | `logs-container` |
| Container (Page Blob demo) | `data-container` |

> Storage account names must be globally unique, 3–24 characters, lowercase letters and numbers only. Change `mystgappenddemo123` if it's taken.

---

## Part 1: Setup

### Step 1: Create a Resource Group
A logical container that holds all the Azure resources for this lab.

```bash
az group create --name rg-storage-lab --location centralindia
```

### Step 2: Create a Storage Account
The main service used to store blobs (files).

```bash
az storage account create \
  --name mystgappenddemo123 \
  --resource-group rg-storage-lab \
  --location centralindia \
  --sku Standard_LRS \
  --kind StorageV2
```

### Step 3: Get the Storage Account Key
Used to authenticate the following commands. This is less secure than identity-based access (see [Notes](#notes)).

```bash
STORAGE_KEY=$(az storage account keys list \
  --account-name mystgappenddemo123 \
  --resource-group rg-storage-lab \
  --query "[0].value" -o tsv)
```

---

## Part 2: Append Blob

### Step 4: Create a Container (`logs-container`)
Holds the log files for the append blob demo.

```bash
az storage container create \
  --name logs-container \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY
```

### Step 5: Create an Append Blob (Initial Log File)
Uploads the first log entry and creates the blob as an append blob.

```bash
echo "Initial log" > app-log.txt && \
az storage blob upload \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name logs-container \
  --name app-log.txt \
  --file app-log.txt \
  --type append
```

### Step 6: Append Data to the Existing Blob
Adds a new log entry to the end of the blob without overwriting what's already there.

```bash
echo "Second log entry $(date)" > app-log.txt && \
az storage blob upload \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name logs-container \
  --name app-log.txt \
  --file app-log.txt \
  --type append
```

> The local `app-log.txt` now holds only the second entry, but the blob in Azure holds both.

### Step 7: Download the Blob
Downloads the blob to confirm it contains both log entries.

```bash
az storage blob download \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name logs-container \
  --name app-log.txt \
  --file app-log.txt

cat app-log.txt
```

**Expected output:**
```
Initial log
Second log entry <current date and time>
```

### Step 8: List Blobs with Their Type
Shows each blob's type (`AppendBlob`, `PageBlob` or `BlockBlob`).

```bash
az storage blob list \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name logs-container \
  --query "[].{Name:name,Type:properties.blobType}" -o table
```

**Expected output:**
```
Name         Type
-----------  ----------
app-log.txt  AppendBlob
```

---

## Part 3: Page Blob

### Step 9: Create Another Container (`data-container`)
Holds the page blob for this demo.

```bash
az storage container create \
  --name data-container \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY
```

### Step 10: Create a Page Blob (512 bytes)
Page blob data must be aligned to 512-byte pages; they're used for VHD disks. This creates a 512-byte file of zeros and uploads it as a page blob.

```bash
head -c 512 /dev/zero > page.bin && \
az storage blob upload \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name data-container \
  --name mypageblob.vhd \
  --file page.bin \
  --type page
```

### Step 11: List Containers
Shows all containers in the storage account.

```bash
az storage container list \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY -o table
```

### Step 12: Confirm the Page Blob Type
Checks that the uploaded blob is a `PageBlob`.

```bash
az storage blob list \
  --account-name mystgappenddemo123 \
  --account-key $STORAGE_KEY \
  --container-name data-container \
  --query "[].{Name:name,Type:properties.blobType}" -o table
```

**Expected output:**
```
Name            Type
--------------  --------
mypageblob.vhd  PageBlob
```

---

## Cleanup (Optional)

Delete the resource group and everything in it to avoid charges:

```bash
az group delete --name rg-storage-lab --yes --no-wait
```

---

## Notes

### Blob Types

| Blob Type | Used For | Key Behavior |
|---|---|---|
| **Append Blob** | Logs, audit trails | Data can only be added to the end; existing data isn't modified |
| **Page Blob** | VM disks (VHD) | Random read/write in 512-byte pages |
| **Block Blob** | General files (images, documents, backups) | Default type; built from blocks, good for upload/download |

### Key Concepts

- **Containers** group blobs logically inside a storage account.
- **Storage account keys** give full access to the whole account. They're fine for a lab, but not recommended for production — use Microsoft Entra ID (`--auth-mode login`), managed identities or SAS tokens instead.
