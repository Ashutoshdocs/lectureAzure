# Azure Blob Storage: Snapshot vs Version

## Practical Lab --- Create, Modify, Compare, and Restore Blob Data

**Audience:** Azure beginners and cloud/DevOps learners\
**Tools:** Azure Portal, Azure CLI, Bash, Microsoft Entra ID\
**Estimated time:** 45--60 minutes

------------------------------------------------------------------------

## 1. Learning objectives

By the end of this lab, you will be able to:

-   Create an Azure Storage Account and Blob container.
-   Upload a file and create a manual blob snapshot.
-   Modify a blob and observe how a snapshot preserves its earlier
    state.
-   Enable Blob Versioning and observe Azure automatically create
    versions.
-   List, download, and restore an earlier version.
-   Explain the difference between a snapshot, a version, and soft
    delete.
-   Choose the appropriate data-protection feature for a real workload.

## 2. Snapshot vs Version --- the simple explanation

Imagine that you maintain a file named `config.txt`.

At 10:00 AM, it contains:

``` text
APP_ENV=DEV
APP_PORT=8080
```

At 10:15 AM, you are about to make a risky change. You manually create a
**snapshot**. This is like taking a photograph of the file at that exact
moment.

At 10:30 AM, someone changes the file to:

``` text
APP_ENV=PROD
APP_PORT=9090
```

The snapshot still contains the earlier content. You can use it to
recover the old state.

Now imagine that Blob Versioning is enabled. Every supported write to
the blob automatically creates a new version. You do not need to
remember to take a snapshot before every change.

```{=html}
<details>
```
```{=html}
<summary>
```
Conceptual timeline
```{=html}
</summary>
```
``` text
SNAPSHOT — manually created by you

10:00  Upload config.txt (DEV, port 8080)
10:15  Create snapshot S1  --------------------> preserves DEV, 8080
10:30  Overwrite base blob with PROD, 9090
       Base blob = PROD, 9090
       Snapshot S1 = DEV, 8080


VERSIONING — automatically managed by Azure

10:00  Upload config.txt (DEV, port 8080)  -> Version V1 (current)
10:30  Overwrite with PROD, 9090           -> V1 becomes previous
                                              V2 becomes current
11:00  Overwrite with QA, 7070             -> V2 becomes previous
                                              V3 becomes current
```

```{=html}
</details>
```
**One-line difference:**

-   **Snapshot:** You decide when to capture a point-in-time copy.
-   **Version:** Azure automatically keeps previous blob states when
    supported write operations occur and versioning is enabled.

Microsoft recommends Blob Versioning for automatic protection of block
blobs against accidental overwrites and deletes. Snapshots are useful
for deliberate checkpoints. See the official documentation in the
References section.

## 3. Comparison table

  -----------------------------------------------------------------------
  Feature                 Blob Snapshot           Blob Versioning
  ----------------------- ----------------------- -----------------------
  Creation                Manual /                Automatic when enabled
                          application-driven      

  Trigger                 You run a snapshot      Supported writes and
                          operation               deletes

  Purpose                 Deliberate              History of changes
                          point-in-time           
                          checkpoint              

  Identifier              Snapshot timestamp      Version ID

  Data state              Read-only copy          Immutable previous
                                                  version

  Restore                 Copy snapshot content   Copy/download a
                          back to base blob       previous version to
                                                  create the desired
                                                  current content

  Setup                   No account-level        Enable at the Storage
                          versioning switch       Account level
                          required                

  Best use                Before a planned        Ongoing protection from
                          deployment or risky     accidental overwrites
                          update                  

  Cost                    Stored data and         Every retained version
                          operations can incur    can add storage and
                          charges                 operation costs

  HNS / ADLS Gen2         Snapshot feature is not Versioning is not
                          supported for           supported for
                          HNS-enabled accounts    HNS-enabled accounts
  -----------------------------------------------------------------------

**Important:** A snapshot or version is not a complete backup of the
Storage Account. Neither protects you from deleting the entire container
or Storage Account. Use container soft delete, appropriate
account/resource protection, and a backup/DR design for broader
protection.

## 4. Prerequisites

-   An Azure subscription.
-   Azure CLI installed.
-   Permission to create Storage Accounts.
-   For data operations using Microsoft Entra ID, a role such as
    **Storage Blob Data Contributor** on the Storage Account or
    container.

Check your CLI:

``` bash
az version
az login
az account show --output table
```

If you have multiple subscriptions, select the correct one:

``` bash
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

## 5. Create the Storage Account

We will create a Standard general-purpose v2 account with hierarchical
namespace (HNS) disabled. This is important because this lab
demonstrates both snapshots and versioning, which are not supported on
HNS-enabled accounts.

``` bash
RG="rg-blob-protection-lab"
LOCATION="centralindia"
STG="stgbloblab$(date +%s)"
CONTAINER="demo"

az group create \
  --name "$RG" \
  --location "$LOCATION"

az storage account create \
  --name "$STG" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace false \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2
```

Check the account:

``` bash
az storage account show \
  --name "$STG" \
  --resource-group "$RG" \
  --query "{name:name,kind:kind,sku:sku.name,hns:isHnsEnabled}" \
  --output table
```

Expected: `kind` should be `StorageV2` and `hns` should be `false`.

### 5.1 Assign data-plane access

Management permissions to create the account do not automatically
guarantee permission to read and write blob contents.

Assign yourself the Blob Data Contributor role:

``` bash
USER_ID=$(az ad signed-in-user show --query id --output tsv)
STG_ID=$(az storage account show \
  --name "$STG" \
  --resource-group "$RG" \
  --query id --output tsv)

az role assignment create \
  --assignee "$USER_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STG_ID"
```

Role assignment propagation can take a few minutes. If a data command
returns an authorization error, wait and retry.

### 5.2 Create a container

``` bash
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STG" \
  --auth-mode login
```

## 6. Practical A --- Create and test a Snapshot

### Step 1: Create a sample file

``` bash
cat > config.txt <<'EOF'
APP_NAME=TrainingApp
APP_ENV=DEV
APP_PORT=8080
VERSION=1.0
EOF

cat config.txt
```

### Step 2: Upload the file

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --file "config.txt" \
  --auth-mode login \
  --overwrite true
```

Verify:

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --auth-mode login \
  --output table
```

### Step 3: Create a snapshot manually

``` bash
az storage blob snapshot \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --auth-mode login \
  --output json
```

Save the snapshot response. It includes the snapshot timestamp.

**Teaching point:** Azure did not create this snapshot automatically
just because the blob was uploaded. You explicitly requested it.

### Step 4: Change the original file

``` bash
cat > config.txt <<'EOF'
APP_NAME=TrainingApp
APP_ENV=PROD
APP_PORT=9090
VERSION=2.0
EOF

cat config.txt
```

Upload the modified file, overwriting the base blob:

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --file "config.txt" \
  --auth-mode login \
  --overwrite true
```

### Step 5: Download the current blob

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --file "current-config.txt" \
  --auth-mode login \
  --overwrite true

cat current-config.txt
```

Expected: `APP_ENV=PROD`, port `9090`, version `2.0`.

### Step 6: List snapshots

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --include s \
  --auth-mode login \
  --query "[?snapshot!=null].{Name:name,Snapshot:snapshot}" \
  --output table
```

The snapshot timestamp is associated with the blob. Use the exact
timestamp returned by the snapshot command or list command.

### Step 7: Download the snapshot

Set `SNAPSHOT` to the timestamp returned by Azure:

``` bash
SNAPSHOT="<PASTE_SNAPSHOT_TIMESTAMP_HERE>"

az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --snapshot "$SNAPSHOT" \
  --file "snapshot-config.txt" \
  --auth-mode login \
  --overwrite true

cat snapshot-config.txt
```

Expected: the snapshot still contains `APP_ENV=DEV`, port `8080`, and
version `1.0`.

### Step 8: Restore the snapshot content

A snapshot is read-only. To restore the base blob, copy the snapshot
content over the base blob.

One straightforward teaching method is to upload the downloaded snapshot
file as the current blob:

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --file "snapshot-config.txt" \
  --auth-mode login \
  --overwrite true
```

Download the base blob again to verify:

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "config.txt" \
  --file "restored-config.txt" \
  --auth-mode login \
  --overwrite true

cat restored-config.txt
```

Expected: the base blob now contains the earlier DEV configuration. The
snapshot itself remains read-only.

**Teaching point:** Restoring means writing the snapshot's content back
as the current blob. It does not make the snapshot editable.

## 7. Practical B --- Enable Blob Versioning

Versioning is an account-level data-protection setting. Enable it before
performing the writes you want to capture.

> For a clean demonstration, use a fresh blob name such as
> `version-demo.txt`. The earlier snapshot exercise can remain in the
> same container.

### Step 1: Enable versioning

``` bash
az storage account blob-service-properties update \
  --account-name "$STG" \
  --resource-group "$RG" \
  --enable-versioning true
```

Verify:

``` bash
az storage account blob-service-properties show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --query "isVersioningEnabled" \
  --output tsv
```

Expected: `true`.

### Step 2: Create Version 1

``` bash
cat > version-demo.txt <<'EOF'
APP_ENV=DEV
APP_PORT=8080
RELEASE=1
EOF

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --file "version-demo.txt" \
  --auth-mode login \
  --overwrite true
```

With versioning enabled, the uploaded blob has a version ID.

### Step 3: Modify the blob --- Version 2

``` bash
cat > version-demo.txt <<'EOF'
APP_ENV=QA
APP_PORT=8081
RELEASE=2
EOF

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --file "version-demo.txt" \
  --auth-mode login \
  --overwrite true
```

### Step 4: Modify it again --- Version 3

``` bash
cat > version-demo.txt <<'EOF'
APP_ENV=PROD
APP_PORT=9090
RELEASE=3
EOF

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --file "version-demo.txt" \
  --auth-mode login \
  --overwrite true
```

### Step 5: List all versions

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --include v \
  --auth-mode login \
  --query "[?name=='version-demo.txt'].{Name:name,VersionId:versionId,Current:isCurrentVersion}" \
  --output table
```

You should see multiple version IDs. One is the current version; the
others are previous versions.

If the result is empty or you see only one version, confirm that
versioning was enabled before the uploads and that each upload changed
the blob.

### Step 6: Download a previous version

Copy a `VersionId` from the previous-version rows:

``` bash
VERSION_ID="<PASTE_PREVIOUS_VERSION_ID_HERE>"

az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --version-id "$VERSION_ID" \
  --file "previous-version.txt" \
  --auth-mode login \
  --overwrite true

cat previous-version.txt
```

You should see the content from the selected earlier version.

### Step 7: Restore a previous version

To make an older version the current content, upload the downloaded file
over the base blob:

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --file "previous-version.txt" \
  --auth-mode login \
  --overwrite true
```

This creates another write and therefore another current version. It
does not erase the existing version history.

Verify the current content:

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --file "version-current-after-restore.txt" \
  --auth-mode login \
  --overwrite true

cat version-current-after-restore.txt
```

## 8. What happens when you delete a versioned blob?

When versioning is enabled and you delete a blob without specifying a
version ID, Azure removes the current blob from the normal current-blob
view and preserves its previous versions. You can still list and recover
those previous versions.

Try this only after completing the earlier steps:

``` bash
az storage blob delete \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "version-demo.txt" \
  --auth-mode login
```

List the versions again:

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --include v \
  --auth-mode login \
  --query "[?name=='version-demo.txt'].{Name:name,VersionId:versionId,Current:isCurrentVersion}" \
  --output table
```

To bring back the content, download a previous version and upload it as
the base blob, following Steps 6 and 7.

**Important:** Versioning does not protect against deletion of the whole
container or Storage Account. Configure container soft delete for
container-level recovery and protect the account resource with
appropriate permissions and locks.

## 9. Azure Portal practical

### Snapshot

1.  Open the Azure Portal.
2.  Open your Storage Account.
3.  Go to **Data storage → Containers**.
4.  Open the `demo` container.
5.  Select `config.txt`.
6.  Find the snapshot action in the blob toolbar or context menu.
7.  Create a snapshot.
8.  Modify or upload a new `config.txt`.
9.  Reopen the blob and inspect its snapshots.
10. Download the snapshot to compare its contents with the current blob.

Portal labels can change slightly over time.

### Versioning

1.  Open the Storage Account.
2.  Go to **Data management → Data protection**.
3.  Enable **Versioning** for blobs and save.
4.  Open the `demo` container.
5.  Upload `version-demo.txt`.
6.  Upload a modified file with the same name.
7.  Open the blob and inspect its version history.
8.  Select an older version to view or download it.
9.  Restore the required content by copying or uploading it as the
    current blob.

## 10. Important production considerations

### 10.1 Versioning and snapshots are not the same as backup

They protect blob data at the object level. They do not automatically
protect the entire Storage Account, its configuration, or a deleted
container.

### 10.2 Watch storage costs

-   Every retained version can contribute to storage charges.
-   Snapshots can also add storage charges.
-   Repeated uploads of large files can create substantial historical
    data.
-   Use Azure Blob Lifecycle Management to delete older versions or
    snapshots according to a retention policy.
-   Monitor storage capacity and transaction costs.

### 10.3 Versioning limitations

-   Blob Versioning is not supported for accounts with hierarchical
    namespace enabled.
-   Not every possible write operation creates a version. For example,
    certain page-blob and append-blob operations are exceptions. Check
    the current Microsoft documentation for the exact operation list.
-   Microsoft recommends keeping fewer than 1,000 versions per blob to
    avoid performance impacts on listing operations.
-   Existing blobs that predate enabling versioning do not automatically
    gain a complete history of their earlier states.

### 10.4 Snapshot limitations

-   A snapshot is read-only; you cannot modify its content.
-   You cannot create a snapshot of an archived blob.
-   Snapshots are not supported on HNS-enabled Data Lake Storage Gen2
    accounts.
-   A snapshot of a blob is not a snapshot of the whole container or
    Storage Account.
-   When versioning is enabled, snapshots of block blobs are generally
    redundant. Creating a snapshot of a versioned blob can also create a
    version, increasing stored objects and cost.

## 11. Which one should you choose?

  -----------------------------------------------------------------------
  Scenario                            Recommended approach
  ----------------------------------- -----------------------------------
  Automatically preserve earlier blob Blob Versioning
  content after updates               

  Create a checkpoint before a        Snapshot
  planned deployment                  

  Recover from accidental overwrite   Blob Versioning
  of a block blob                     

  Capture a point-in-time state for a Snapshot
  workflow that explicitly requests   
  it                                  

  Protect against accidental blob     Versioning plus Blob soft delete
  deletion                            

  Protect against container deletion  Container soft delete

  Protect against Storage Account     Resource locks, access controls,
  deletion                            and a broader backup/DR plan

  HNS-enabled ADLS Gen2 account       Use supported alternatives such as
                                      soft delete and backup options;
                                      snapshots and versioning are
                                      unavailable
  -----------------------------------------------------------------------

**Practical recommendation:** For a standard Blob Storage account with
critical block blobs, consider enabling versioning and blob soft delete
together, then use lifecycle management to control retention and cost.
Use snapshots for deliberate checkpoints when versioning is unavailable
or when a specific workflow requires them.

## 12. Student assignment

Complete these tasks without copying the earlier output:

1.  Create a new text file called `student.txt` and upload it.
2.  Create two snapshots at different times, with a content change
    between them.
3.  Download both snapshots and compare their contents.
4.  Enable versioning on a suitable non-HNS Storage Account.
5.  Upload the same blob three times with different content.
6.  List the version IDs and identify the current version.
7.  Download an older version and restore its content as the current
    blob.
8.  Explain why the restore operation creates another version.
9.  Explain why versioning alone cannot recover a deleted container.
10. Propose a lifecycle rule to remove old versions after an agreed
    retention period.

## 13. Interview questions

1.  What is an Azure Blob snapshot?
2.  Is a snapshot writable?
3.  Do you need to enable an account-level setting before creating a
    snapshot?
4.  What is Blob Versioning?
5.  What event creates a new blob version?
6.  What is the difference between a snapshot timestamp and a version
    ID?
7.  What happens to previous versions when the current version is
    deleted?
8.  How do you restore a previous version?
9.  Does Blob Versioning protect against container deletion?
10. Can you enable Blob Versioning on an HNS-enabled Storage Account?
11. How can lifecycle management help control versioning costs?
12. Why might snapshots be redundant after enabling versioning?

## 14. Cleanup

After completing the lab, remove the resource group and all resources
inside it:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

This permanently deletes the lab Storage Account and its data. Do not
run this command against a production resource group.

## 15. Official Microsoft references

-   [Blob
    snapshots](https://learn.microsoft.com/en-us/azure/storage/blobs/snapshots-overview)
-   [Blob versioning
    overview](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview)
-   [Enable and manage Blob
    Versioning](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-enable)
-   [Blob soft
    delete](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview)
-   [Azure Storage data protection
    overview](https://learn.microsoft.com/en-us/azure/storage/blobs/data-protection-overview)

------------------------------------------------------------------------

**Trainer's closing explanation:**

A snapshot is like manually taking a photograph before making a risky
change. Versioning is like automatically maintaining a history whenever
supported changes happen. Both help recover blob content, but neither
replaces a complete backup and disaster-recovery strategy.
