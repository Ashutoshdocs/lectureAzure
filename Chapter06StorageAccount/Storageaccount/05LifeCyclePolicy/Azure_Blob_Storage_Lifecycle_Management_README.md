# Azure Blob Storage -- Lifecycle Management Practical Lab

## Chapter objective

In this chapter, you will learn how Azure Blob Storage Lifecycle
Management automates data retention and access-tier transitions. You
will create a Storage Account, upload sample blobs, build a JSON
lifecycle policy, apply it using Azure CLI, inspect it in the Azure
Portal, and understand how rules are evaluated.

**Real-world scenario:** A company stores millions of application logs,
reports, and backups. Instead of writing a script that checks every
blob, the company defines lifecycle rules that automatically move
eligible data to cheaper tiers or delete data when it is no longer
required.

------------------------------------------------------------------------

## 1. What is Lifecycle Management?

Azure Blob Storage Lifecycle Management is a policy-based feature for
managing the lifecycle of supported blob data.

You define rules in JSON. A rule can:

-   Move eligible block blobs to Cool, Cold, or Archive.
-   Delete eligible base blobs.
-   Delete previous versions or snapshots after a specified age.
-   Apply to all eligible blobs or to a filtered subset using prefixes
    and blob index tags.

Lifecycle policies are evaluated periodically and asynchronously. A
policy change or a condition becoming true does not cause an immediate
transition. Evaluation can take up to 24 hours to begin or reflect a
change, and processing a large number of blobs can take additional time.

**Important:** Lifecycle Management is not a real-time monitoring
service. It evaluates policy conditions periodically.

## 2. How a lifecycle rule works

A rule generally contains:

1.  `name` -- unique name for the rule.
2.  `enabled` -- whether the rule is active.
3.  `type` -- `Lifecycle`.
4.  `definition.filters` -- which blobs the rule applies to.
5.  `definition.actions` -- what to do with eligible blobs.

Conceptual example:

``` text
Blob uploaded
     |
     v
Lifecycle policy evaluation
     |
     v
Does the blob match the filter?
     |
     v
Is the age condition satisfied?
     |
     +---- No ----> Do nothing; evaluate in a later run
     |
    Yes
     |
     v
Perform configured action
     |
     +---- Move to Cool
     +---- Move to Cold
     +---- Move to Archive
     +---- Delete
```

## 3. Important concepts and limitations

-   Lifecycle policies support block blobs and append blobs for
    supported actions. Tiering actions such as Cool, Cold, and Archive
    apply to block blobs; do not assume append blobs can be tiered.
-   Page blobs are not managed by Blob Lifecycle Management.
-   Lifecycle rules do not manage the storage account's system
    containers.
-   Filters can use blob type, blob name prefixes, and blob index tags.
-   Actions can target base blobs, snapshots, and previous versions,
    subject to action support and account configuration.
-   Lifecycle Management does not rehydrate archived blobs.
-   Lifecycle Management does not support changing the access tier of a
    blob that is currently in Archive. Rehydrate it separately.
-   For tier transitions, check supported account types, redundancy
    options, and feature combinations in the current Microsoft
    documentation.
-   Deleting or moving data before a tier's minimum retention period can
    result in early-deletion charges.
-   A rule based on last access time requires access-time tracking to be
    enabled. Last modified time and last access time are different
    measurements.

### Minimum retention periods to remember

  Tier        Minimum retention period
  --------- --------------------------
  Cool                         30 days
  Cold                         90 days
  Archive                     180 days

These periods are relevant to early-deletion billing, not a requirement
that every blob must remain in a tier before a lifecycle rule can be
configured.

## 4. Practical architecture

``` text
Azure Subscription
       |
Resource Group: rg-lifecycle-demo
       |
Storage Account: StorageV2
       |
Container: company-data
       |
       +-- logs/app-01.txt
       +-- logs/app-02.txt
       +-- reports/annual-report.txt
       +-- backup/database-backup.txt
                 |
                 v
       Lifecycle Management Policy
                 |
          Age / filter conditions
                 |
       +---------+----------+
       |         |          |
      Cool     Archive    Delete
```

## 5. Prerequisites

-   An Azure subscription
-   Azure CLI installed
-   Linux, Ubuntu, or WSL terminal
-   Permission to create resource groups and storage accounts
-   Permission to create or update storage account management policies
-   `Storage Blob Data Contributor` role for Entra ID-based blob uploads
    and listings

Check Azure CLI:

``` bash
az version
```

## 6. Sign in and set variables

``` bash
az login
az account show --output table
```

If necessary, select a subscription:

``` bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

Define the lab variables:

``` bash
RG="rg-lifecycle-demo"
LOCATION="centralindia"
STG="stglifecycle$(date +%s)"
CONTAINER="company-data"

echo "$STG"
```

Storage account names must be globally unique, lowercase, and 3--24
characters.

## 7. Create a resource group

``` bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

Verify:

``` bash
az group show --name "$RG" --output table
```

## 8. Create a Storage Account

Create a Standard General Purpose v2 account:

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

Verify:

``` bash
az storage account show \
  --name "$STG" \
  --resource-group "$RG" \
  --query "{Name:name,Kind:kind,Tier:accessTier,SKU:sku.name}" \
  --output table
```

## 9. Assign blob data access and create a container

Assign the data-plane role to the signed-in user:

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

Role assignments can take several minutes to propagate.

Create the container:

``` bash
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STG" \
  --auth-mode login
```

## 10. Create and upload sample blobs

Create sample folders and files locally:

``` bash
mkdir -p lifecycle-lab/logs lifecycle-lab/reports lifecycle-lab/backup

echo "Application log 01" > lifecycle-lab/logs/app-01.txt
echo "Application log 02" > lifecycle-lab/logs/app-02.txt
echo "Annual company report" > lifecycle-lab/reports/annual-report.txt
echo "Database backup metadata" > lifecycle-lab/backup/database-backup.txt
```

Upload them, preserving the virtual folder names in blob names:

``` bash
az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "logs/app-01.txt" \
  --file lifecycle-lab/logs/app-01.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "logs/app-02.txt" \
  --file lifecycle-lab/logs/app-02.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "reports/annual-report.txt" \
  --file lifecycle-lab/reports/annual-report.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "backup/database-backup.txt" \
  --file lifecycle-lab/backup/database-backup.txt \
  --tier Hot \
  --auth-mode login
```

List the blobs:

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --auth-mode login \
  --output table
```

## 11. Create a lifecycle policy JSON file

Create a file named `lifecycle-policy.json`:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "MoveLogsToCool",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": [
            "blockBlob"
          ],
          "prefixMatch": [
            "company-data/logs/"
          ]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            }
          }
        }
      }
    }
  ]
}
```

**Understand the policy:**

-   `rules`: an array; a policy can contain multiple rules.
-   `enabled`: `true` means the rule is active. Set it to `false` to
    disable it.
-   `name`: the rule name.
-   `type`: lifecycle rule type.
-   `blobTypes`: the rule applies to block blobs.
-   `prefixMatch`: limits the rule to matching blob names.
-   `baseBlob`: actions for the current/base blob.
-   `tierToCool`: moves an eligible blob to Cool.
-   `daysAfterModificationGreaterThan`: condition based on the number of
    days since the blob was last modified.

**Prefix matching detail:** The prefix includes the container name. For
a container called `company-data`, a blob named `logs/app-01.txt` is
addressed by the lifecycle filter prefix `company-data/logs/`.

## 12. Apply the lifecycle policy

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @lifecycle-policy.json
```

Verify the configured policy:

``` bash
az storage account management-policy show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --output json
```

The policy is now configured. Do not expect a newly uploaded file to
move tiers immediately: this example requires the blob to be more than
30 days past its last modification, and policy evaluation is
asynchronous.

## 13. Add more lifecycle actions

The following example demonstrates several actions in one policy. Use it
as a separate example or replace the previous policy after reviewing the
rules.

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "TierApplicationLogs",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/logs/"]
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
            },
            "delete": {
              "daysAfterModificationGreaterThan": 730
            }
          }
        }
      }
    }
  ]
}
```

This is an illustrative progression. Validate action compatibility and
minimum retention implications before deploying. Lifecycle policies are
evaluated periodically, so the actions are not guaranteed to occur at
the exact day boundary.

To apply the second example, save it as `lifecycle-policy.json` and run
the management-policy create command from the previous section.

## 14. Example -- Delete old data

Suppose temporary application logs should be deleted after 365 days.

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "DeleteOldLogs",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/logs/"]
        },
        "actions": {
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": 365
            }
          }
        }
      }
    }
  ]
}
```

The policy deletes eligible base blobs after they satisfy the configured
age condition. Test deletion rules carefully; deletion is not a
substitute for a backup or retention strategy.

## 15. Example -- Manage previous versions and snapshots

Lifecycle Management can also manage previous blob versions and
snapshots when versioning or snapshots are configured.

Illustrative policy fragment:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "DeleteOldVersionsAndSnapshots",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/"]
        },
        "actions": {
          "version": {
            "delete": {
              "daysAfterCreationGreaterThan": 90
            }
          },
          "snapshot": {
            "delete": {
              "daysAfterCreationGreaterThan": 90
            }
          }
        }
      }
    }
  ]
}
```

This is an example of version and snapshot retention actions. Enable the
relevant blob versioning or snapshot features and validate the policy
schema and behavior for your account before use.

## 16. Configure Lifecycle Management using Azure Portal

1.  Open the Azure Portal.
2.  Go to **Storage accounts**.
3.  Select the lab storage account.
4.  Under **Data management**, select **Lifecycle management**.
5.  Select **Add a rule**.
6.  Enter a rule name, such as `MoveLogsToCool`.
7.  Choose the scope:
    -   Apply to all blobs.
    -   Limit using filters.
8.  Choose the blob type, such as block blobs.
9.  Select the base blob, versions, or snapshots as appropriate.
10. Add a condition such as **Last modified** greater than 30 days.
11. Choose an action such as **Move to Cool**.
12. Review and add the rule.
13. Open the policy's code view to inspect its JSON representation.

Portal labels may change as the Azure Portal evolves.

## 17. Last modified time versus last access time

These are different conditions.

  -----------------------------------------------------------------------
  Condition                           Meaning
  ----------------------------------- -----------------------------------
  Last modified                       Time when blob content or
                                      properties were last modified

  Last access                         Time when the blob was last
                                      read/accessed, when access-time
                                      tracking is enabled
  -----------------------------------------------------------------------

A policy using `daysAfterModificationGreaterThan` does not mean the blob
has not been read for that number of days.

To use last access time:

1.  Enable blob access-time tracking on the storage account.
2.  Allow the tracking data to be updated.
3.  Use the `daysAfterLastAccessTimeGreaterThan` condition in a
    supported lifecycle action.

Example action:

``` json
"tierToCool": {
  "daysAfterLastAccessTimeGreaterThan": 30
}
```

Access-time tracking and lifecycle evaluation are not real-time. Check
the current Microsoft documentation for tracking behavior, supported
conditions, and any billing implications.

## 18. Disable or delete a lifecycle rule

To disable a rule, edit the JSON and set:

``` json
"enabled": false
```

Then update the storage account management policy using the revised
JSON:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @lifecycle-policy.json
```

To remove the entire management policy:

``` bash
az storage account management-policy delete \
  --account-name "$STG" \
  --resource-group "$RG"
```

Use the delete command only when you intend to remove the complete
lifecycle policy from the storage account.

## 19. Student assignment

Complete these tasks independently:

-   [ ] Create a resource group and StorageV2 account.
-   [ ] Create a container named `student-data`.
-   [ ] Upload files into `logs/`, `reports/`, and `backup/` prefixes.
-   [ ] Create a lifecycle rule that targets only `logs/`.
-   [ ] Configure a rule to move eligible logs to Cool after 30 days
    since modification.
-   [ ] Add a separate rule to delete eligible temporary files after 365
    days.
-   [ ] Inspect the JSON code view in Azure Portal.
-   [ ] Disable one rule and verify the policy.
-   [ ] Explain why a lifecycle policy does not execute immediately.
-   [ ] Explain the difference between last modified time and last
    access time.

## 20. Interview questions

1.  What is Azure Blob Storage Lifecycle Management?
2.  Why is Lifecycle Management useful when a storage account contains
    millions of blobs?
3.  What is a lifecycle policy?
4.  What is the purpose of `prefixMatch`?
5.  What is the difference between `daysAfterModificationGreaterThan`
    and `daysAfterLastAccessTimeGreaterThan`?
6.  Does Lifecycle Management run immediately after a blob is uploaded?
7.  Can Lifecycle Management rehydrate an archived blob?
8.  Can lifecycle rules manage previous versions and snapshots?
9.  Which blob types are supported?
10. What is the difference between manually changing an access tier and
    using Lifecycle Management?

## 21. Cleanup

Delete the lab resource group after the practical:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

This deletes the storage account and all resources in the lab resource
group.

## 22. Official Microsoft documentation

-   [Azure Blob Storage lifecycle management
    overview](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
-   [Lifecycle management policy
    structure](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-structure)
-   [Lifecycle management policy actions and
    conditions](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-access-tiers)
-   [Enable and manage blob access time
    tracking](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-access-time-tracking)

------------------------------------------------------------------------

## Chapter outcome

By the end of this chapter, students should understand how to create
JSON-based lifecycle policies, filter blobs by container path, automate
access-tier transitions, delete old data, manage previous versions and
snapshots, and distinguish last modified time from last access time.
