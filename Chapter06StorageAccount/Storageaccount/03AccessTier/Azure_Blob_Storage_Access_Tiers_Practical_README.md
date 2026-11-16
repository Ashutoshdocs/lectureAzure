# Azure Blob Storage -- Access Tiers Practical Lab

## Chapter objective

In this chapter, you will learn how to create an Azure Storage Account,
upload files to Blob Storage, inspect access tiers, move blobs between
Hot, Cool, Cold, and Archive, restore archived data, and automate tier
transitions with Lifecycle Management.

**Scenario:** A company stores application logs, reports, and backups in
Azure Blob Storage. Frequently accessed files stay in Hot. Older files
are moved to cooler tiers to reduce storage costs.

------------------------------------------------------------------------

## 1. Understand the access tiers

  --------------------------------------------------------------------------
  Tier         Best for           Storage cost      Access cost Access
  ------------ -------------- ---------------- ---------------- ------------
  Hot          Frequently              Highest           Lowest Online
               accessed data                                    

  Cool         Infrequently              Lower           Higher Online
               accessed data                                    

  Cold         Rarely          Lower than Cool Higher than Cool Online
               accessed data                                    
               that still                                       
               needs fast                                       
               retrieval                                        

  Archive      Rarely                   Lowest          Highest Offline
               accessed,                                        
               long-term                                        
               retention                                        
  --------------------------------------------------------------------------

Minimum recommended retention periods for a general-purpose v2 account:

-   Cool: 30 days
-   Cold: 90 days
-   Archive: 180 days

**Important concepts**

-   Hot, Cool, and Cold are online tiers. Data can be read immediately.
-   Archive is offline. A blob must be rehydrated to Hot, Cool, or Cold
    before its contents can be read or downloaded.
-   Standard-priority archive rehydration can take up to 15 hours;
    actual time varies.
-   Moving data to a cooler tier reduces capacity cost but can increase
    read, write, transaction, and retrieval charges.
-   Early deletion charges can apply if a blob is deleted, overwritten,
    or moved before the tier's minimum retention period has elapsed.
-   Tier changes apply to supported block blobs. Check current feature
    and redundancy limitations before using Archive.

## 2. Practical architecture

``` text
Azure Subscription
       |
Resource Group: rg-blob-tier-demo
       |
Storage Account: StorageV2 / Standard_LRS
       |
Container: company-data
       |
       +-- app-logs.txt          Hot -> Cool -> Cold -> Archive
       +-- financial-reports.txt Hot
       +-- backup-data.txt       Hot
```

## 3. Prerequisites

-   An Azure subscription
-   Azure CLI installed
-   A Linux terminal, Ubuntu VM, or WSL
-   Permission to create resource groups and storage accounts
-   Permission to assign Azure RBAC roles, or an administrator who can
    assign the data role
-   `Storage Blob Data Contributor` on the storage account for Entra
    ID-based blob data operations

Check Azure CLI:

``` bash
az version
```

## 4. Set variables and sign in

``` bash
az login
az account show --output table
```

If necessary, select the correct subscription:

``` bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

Set the lab variables. Storage account names must be globally unique,
lowercase, and 3--24 characters.

``` bash
RG="rg-blob-tier-demo"
LOCATION="centralindia"
STG="stgblobtier$(date +%s)"
CONTAINER="company-data"

echo "Storage account: $STG"
```

Keep this terminal open so the variables remain available in later
steps.

## 5. Create the resource group

``` bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

Verify:

``` bash
az group show --name "$RG" --output table
```

## 6. Create the Storage Account

Create a Standard General Purpose v2 account with locally redundant
storage and Hot as its default access tier.

``` bash
az storage account create \
  --name "$STG" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --access-tier Hot \
  --min-tls-version TLS1_2
```

Verify the account:

``` bash
az storage account show \
  --name "$STG" \
  --resource-group "$RG" \
  --query "{Name:name,Kind:kind,Tier:accessTier,SKU:sku.name}" \
  --output table
```

Expected account kind: `StorageV2`; default tier: `Hot`.

## 7. Assign the blob data role

The account-management role `Contributor` alone does not automatically
grant blob data access. For this lab, use the
`Storage Blob Data Contributor` data-plane role.

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

Role assignments can take several minutes to propagate. If the signed-in
identity is not a user identity, use the appropriate service principal
or managed identity object ID.

## 8. Create a blob container

``` bash
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STG" \
  --auth-mode login
```

List containers:

``` bash
az storage container list \
  --account-name "$STG" \
  --auth-mode login \
  --output table
```

## 9. Create sample files

``` bash
mkdir -p blob-lab
cd blob-lab

echo "Application logs - November 2026" > app-logs.txt
echo "Company financial reports" > financial-reports.txt
echo "Historical backup information" > backup-data.txt

ls -lh
```

## 10. Upload the files in Hot tier

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --file app-logs.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name financial-reports.txt \
  --file financial-reports.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name backup-data.txt \
  --file backup-data.txt \
  --tier Hot \
  --auth-mode login
```

List uploaded blobs:

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --auth-mode login \
  --output table
```

## 11. Inspect the current tier

``` bash
az storage blob show \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --auth-mode login \
  --query "{Name:name,Tier:properties.blobTier}" \
  --output table
```

The uploaded blob should show `Hot`.

## 12. Move Hot to Cool

Imagine the application logs are no longer frequently accessed.

``` bash
az storage blob set-tier \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --tier Cool \
  --auth-mode login
```

Verify:

``` bash
az storage blob show \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --auth-mode login \
  --query properties.blobTier \
  --output tsv
```

Expected: `Cool`.

## 13. Move Cool to Cold

``` bash
az storage blob set-tier \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --tier Cold \
  --auth-mode login
```

Verify:

``` bash
az storage blob show \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --auth-mode login \
  --query properties.blobTier \
  --output tsv
```

Expected: `Cold`.

**Teaching note:** This is a demonstration of tier switching, not a
recommendation to move a newly uploaded file through tiers immediately.
In production, consider retention periods and early deletion charges.

## 14. Move Cold to Archive

``` bash
az storage blob set-tier \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --tier Archive \
  --auth-mode login
```

Verify:

``` bash
az storage blob show \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --auth-mode login \
  --query "{Name:name,Tier:properties.blobTier}" \
  --output table
```

Expected tier: `Archive`.

The blob remains listed in the container, but its data is offline.

## 15. Try to download the archived blob

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --file downloaded-logs.txt \
  --auth-mode login
```

The download should fail while the blob is archived. Explain that
Archive is an offline tier, unlike Hot, Cool, and Cold.

## 16. Rehydrate Archive to Hot

When the company needs the archived log, request rehydration:

``` bash
az storage blob set-tier \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --tier Hot \
  --rehydrate-priority Standard \
  --auth-mode login
```

Check the blob properties:

``` bash
az storage blob show \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --auth-mode login \
  --query "{Tier:properties.blobTier,ArchiveStatus:properties.archiveStatus}" \
  --output table
```

During rehydration, the tier can continue to show `Archive`. Wait until
the operation completes and the tier reports `Hot`.

Then download:

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name app-logs.txt \
  --file downloaded-logs.txt \
  --auth-mode login
```

Verify the content:

``` bash
cat downloaded-logs.txt
```

**Important:** Standard-priority rehydration can take up to 15 hours for
eligible blobs under 10 GB. Do not expect this step to finish
immediately.

## 17. Azure Portal practical

Repeat the same operations in the portal:

1.  Open Azure Portal.
2.  Select **Storage accounts**.
3.  Open the lab storage account.
4.  Under **Data storage**, select **Containers**.
5.  Open `company-data`.
6.  Select a blob such as `app-logs.txt`.
7.  Inspect its properties and access tier.
8.  Use the available **Change tier** action to move the blob to Cool,
    Cold, or Archive.
9.  For an archived blob, request a change to an online tier and wait
    for rehydration to complete before downloading.

Portal labels and layouts may change over time.

## 18. Lifecycle Management -- Automate tier transitions

For millions of blobs, administrators should not manually change each
blob's tier. Azure Blob Lifecycle Management evaluates rules and
performs supported transitions automatically.

Create a file named `lifecycle-policy.json`:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "CompanyDataTiering",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToCold": {
              "daysAfterModificationGreaterThan": 90
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 180
            }
          }
        }
      }
    }
  ]
}
```

Apply the policy:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @lifecycle-policy.json
```

Verify:

``` bash
az storage account management-policy show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --output json
```

**Important lifecycle notes:**

-   Lifecycle evaluation is asynchronous; transitions do not happen
    immediately when a threshold is reached.
-   The example uses days since last modification, not days since last
    access.
-   The rules are illustrative. Validate rule behavior, minimum
    retention periods, and account feature support before production
    use.
-   Lifecycle Management cannot rehydrate an archived blob to an online
    tier.
-   Consider adding `daysAfterLastTierChangeGreaterThan` to an archive
    action to avoid unintentionally re-archiving recently rehydrated
    data.

## 19. Storage cost versus operation cost

Azure storage costs include more than capacity:

  -----------------------------------------------------------------------
  Cost component                      Explanation
  ----------------------------------- -----------------------------------
  Capacity                            Amount of data stored, billed
                                      according to tier and redundancy

  Read operations                     Requests to read or retrieve blobs

  Write operations                    Uploading or changing blobs

  Data retrieval                      Data read from applicable cooler
                                      tiers

  Network transfer                    Data transferred out of Azure,
                                      where applicable
  -----------------------------------------------------------------------

General principle:

-   Hot: higher storage cost, lower access and transaction costs.
-   Cool: lower storage cost, higher access costs.
-   Cold: lower storage cost than Cool, higher access costs.
-   Archive: lowest storage cost, but offline retrieval and higher
    retrieval costs.

Always check the pricing calculator for the region, redundancy, data
volume, transaction count, and retrieval pattern.

## 20. Azure Data Lake Storage Gen2

When creating a StorageV2 account, you can enable **Hierarchical
namespace**. This enables Azure Data Lake Storage Gen2 capabilities.

Common data engineering scenarios:

-   Application and infrastructure log ingestion
-   IoT sensor data
-   Large datasets
-   Analytics and data lake workloads
-   Data processing with Azure Databricks and Azure Synapse Analytics

Blob access tiers and ADLS Gen2 capabilities can be used together,
subject to feature compatibility.

## 21. Student assignment

Complete these tasks independently:

-   [ ] Create a resource group.
-   [ ] Create a StorageV2 account with Hot as its default tier.
-   [ ] Create a container named `student-data`.
-   [ ] Upload three text files.
-   [ ] Verify the default Hot tier.
-   [ ] Move `file1.txt` from Hot to Cool.
-   [ ] Move `file2.txt` from Hot to Cold.
-   [ ] Move `file3.txt` from Hot to Archive.
-   [ ] Attempt to download `file3.txt` while archived.
-   [ ] Rehydrate `file3.txt` to Hot.
-   [ ] Download the restored file.
-   [ ] Create and inspect a lifecycle policy.
-   [ ] Explain storage cost versus retrieval cost.

## 22. Interview questions

1.  What are Azure Blob Storage access tiers?
2.  What is the difference between Hot and Cool?
3.  What are the minimum recommended retention periods for Cool, Cold,
    and Archive?
4.  Why can't an archived blob be downloaded immediately?
5.  What is blob rehydration?
6.  What is the difference between storage capacity cost and data
    retrieval cost?
7.  What is an early deletion charge?
8.  Can an archived blob be rehydrated using a lifecycle policy?
9.  What is Azure Blob Lifecycle Management?
10. What is the difference between Blob Storage and ADLS Gen2?

## 23. Cleanup -- Delete lab resources

After completing the practical, delete the resource group to avoid
ongoing charges:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

This removes the storage account and other resources inside the lab
resource group.

## 24. Official Microsoft documentation

-   [Access tiers for blob
    data](https://learn.microsoft.com/en-us/azure/storage/blobs/access-tiers-overview)
-   [Archive a
    blob](https://learn.microsoft.com/en-us/azure/storage/blobs/archive-blob)
-   [Blob rehydration from the Archive
    tier](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-rehydration)
-   [Lifecycle management policy
    structure](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-structure)
-   [Lifecycle policies for access tier
    transitions](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-access-tiers)

------------------------------------------------------------------------

## Chapter outcome

By the end of this chapter, students should be able to create an Azure
Storage Account from scratch, upload files, inspect and change blob
access tiers, understand Archive rehydration, compare storage and
retrieval costs, and automate eligible tier transitions using Lifecycle
Management.
