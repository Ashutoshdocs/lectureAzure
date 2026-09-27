# AzCopy Command Reference

Quick reference for moving files between a local machine and Azure Blob Storage, and between two Azure Storage accounts, using AzCopy.

## Commands

### Local ⇄ Azure Blob

| Action | Direction | Command Format | Example |
|---|---|---|---|
| Upload Single File | Local → Azure Blob | `azcopy copy "local\file" "blob_url/container/?<SAS_token>"` | `azcopy copy "D:\vm2_key.pem" "https://stgblaze123.blob.core.windows.net/mycontainer/?<SAS_token>"` |
| Upload Folder (Recursive) | Local → Azure Blob | `azcopy copy "local_folder" "blob_url/container?<SAS_token>" --recursive=true` | `azcopy copy "D:\mycontainer" "https://stgblaze123.blob.core.windows.net/mycontainer?<SAS_token>" --recursive=true` |
| Download Single File | Azure Blob → Local | `azcopy copy "blob_url/container/file?<SAS_token>" "local\file"` | `azcopy copy "https://stgblaze123.blob.core.windows.net/mycontainer/vm2_key.pem?<SAS_token>" "D:\vm2_key.pem"` |
| Download Container (Recursive) | Azure Blob → Local | `azcopy copy "blob_url/container?<SAS_token>" "local_folder" --recursive=true` | `azcopy copy "https://stgblaze123.blob.core.windows.net/mycontainer?<SAS_token>" "D:\mycontainer" --recursive=true` |

### Storage Account → Storage Account

These copies run server-to-server inside Azure, so data does not pass through your local machine.

| Action | Direction | Command Format | Example |
|---|---|---|---|
| Copy Single Blob | Source Account → Destination Account | `azcopy copy "src_blob_url/container/file?<SRC_SAS>" "dst_blob_url/container/file?<DST_SAS>"` | `azcopy copy "https://stgblaze123.blob.core.windows.net/mycontainer/vm2_key.pem?<SRC_SAS>" "https://stgblaze456.blob.core.windows.net/backupcontainer/vm2_key.pem?<DST_SAS>"` |
| Copy Container (Recursive) | Source Account → Destination Account | `azcopy copy "src_blob_url/container?<SRC_SAS>" "dst_blob_url/container?<DST_SAS>" --recursive=true` | `azcopy copy "https://stgblaze123.blob.core.windows.net/mycontainer?<SRC_SAS>" "https://stgblaze456.blob.core.windows.net/backupcontainer?<DST_SAS>" --recursive=true` |
| Copy Entire Account (All Containers) | Source Account → Destination Account | `azcopy copy "src_blob_url/?<SRC_SAS>" "dst_blob_url/?<DST_SAS>" --recursive=true` | `azcopy copy "https://stgblaze123.blob.core.windows.net/?<SRC_SAS>" "https://stgblaze456.blob.core.windows.net/?<DST_SAS>" --recursive=true` |
| Sync Container (only new/changed) | Source Account → Destination Account | `azcopy sync "src_blob_url/container?<SRC_SAS>" "dst_blob_url/container?<DST_SAS>" --recursive=true` | `azcopy sync "https://stgblaze123.blob.core.windows.net/mycontainer?<SRC_SAS>" "https://stgblaze456.blob.core.windows.net/backupcontainer?<DST_SAS>" --recursive=true` |

> In the examples, `stgblaze123` is the source account and `stgblaze456` is the destination account.

## Notes

### 1. Generate a SAS Token
1. Open the Storage Account.
2. Open the Blob Container.
3. Select **Generate SAS** (Shared Access Signature).
4. Copy the value from the **SAS Token (Signature)** field.

### 2. Get the Container URL
1. Open the Blob Container.
2. Go to the **Properties** tab.
3. Copy the Container URL.
4. Append the SAS Token to the URL before using AzCopy.

Example:

```
https://stgblaze123.blob.core.windows.net/mycontainer?<SAS_token>
```

### 3. SAS Permissions for Account-to-Account Copy
You need a separate SAS token for each account:

| Account | Required Permissions |
|---|---|
| Source | **Read**, **List** |
| Destination | **Write**, **Create** (add **Add** / **List** if using `azcopy sync`) |

- To copy an entire account, generate the SAS at the **Storage Account** level (Storage Account → **Shared access signature**), with allowed resource types **Service**, **Container** and **Object**.
- The destination container is created automatically if it doesn't exist (the destination SAS must allow it).
- Wrap every URL in double quotes — SAS tokens contain `&`, which the shell would otherwise split on.
- Check progress or failures with `azcopy jobs list` and `azcopy jobs show <job-id>`.
