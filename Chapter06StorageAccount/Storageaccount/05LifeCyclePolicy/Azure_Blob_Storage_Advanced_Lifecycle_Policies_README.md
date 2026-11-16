# Azure Blob Storage -- Advanced Lifecycle Management Policies

## Chapter objective

In this chapter, you will build on the basic Lifecycle Management
practical and learn how to design more advanced JSON policies.

You will learn how to:

-   Configure multiple lifecycle rules in one storage account.
-   Scope rules to all blobs, a container, or a virtual folder
    (blob-name prefix).
-   Use conditions based on last modification, creation, and last access
    time.
-   Enable blob access-time tracking.
-   Configure automatic tiering from Cool to Hot when a blob is
    accessed.
-   Manage base blobs and previous versions.
-   Understand what happens when multiple rules target the same blob.
-   Inspect and update the policy using Azure CLI and Azure Portal.

**Scenario:** A company stores application logs in several containers
and virtual folders. Some data is accessed frequently, some is rarely
accessed, and some must eventually be deleted. The company wants Azure
to manage these transitions without a custom script scanning every blob.

------------------------------------------------------------------------

## 1. Lifecycle Management recap

Azure Blob Storage Lifecycle Management uses JSON-based rules. Each rule
contains:

-   A name.
-   An enabled/disabled state.
-   Filters that define which blobs are in scope.
-   Actions to perform.
-   Conditions that determine when actions become eligible.

Lifecycle policies are evaluated periodically and asynchronously. Do not
expect a rule to execute immediately when a blob reaches its age
threshold. Evaluation can take up to 24 hours to begin or reflect a
change, and processing may take longer.

## 2. Lifecycle actions

Common base-blob actions include:

  -----------------------------------------------------------------------
  Action                              Purpose
  ----------------------------------- -----------------------------------
  `tierToCool`                        Move an eligible block blob to Cool

  `tierToCold`                        Move an eligible block blob to Cold

  `tierToArchive`                     Move an eligible block blob to
                                      Archive

  `delete`                            Delete an eligible base blob

  `enableAutoTierToHotFromCool`       Allow an eligible Cool blob to be
                                      automatically moved to Hot when
                                      access-time conditions are met
  -----------------------------------------------------------------------

The exact supported actions depend on blob type, account configuration,
and current Azure feature support. Tiering actions apply to block blobs.
Check the current Microsoft documentation before deploying a policy.

### Important: automatic tiering from Cool to Hot

`enableAutoTierToHotFromCool` is not the same as an ordinary scheduled
tier transition. It enables automatic re-tiering of a Cool blob to Hot
when Azure's access-time tracking detects qualifying access, subject to
the configured last-access condition.

For example, a policy may say:

-   Move a blob to Cool after it has not been modified for 30 days.
-   If it is later accessed while in Cool, automatically move it back to
    Hot.

This is useful when data is usually infrequently accessed but
occasionally becomes active again.

## 3. Conditions used in lifecycle rules

  --------------------------------------------------------------------------
  Condition                              What it measures
  -------------------------------------- -----------------------------------
  `daysAfterModificationGreaterThan`     Days since the blob was last
                                         modified

  `daysAfterCreationGreaterThan`         Days since the blob was created

  `daysAfterLastAccessTimeGreaterThan`   Days since the tracked last-access
                                         time

  `daysAfterLastTierChangeGreaterThan`   Days since the blob's tier was last
                                         changed, where supported
  --------------------------------------------------------------------------

Do not confuse last modification with last access:

-   Reading a blob does not necessarily modify it.
-   A blob can be accessed today even if it was last modified months
    ago.
-   Last-access-based rules require access-time tracking to be enabled.

## 4. Multiple rules and overlapping scope

A lifecycle policy can contain multiple rules. A blob can match more
than one rule if the filters and conditions overlap.

For example:

-   Rule A applies to every blob in the storage account and moves
    eligible data to Cool.
-   Rule B applies only to `company-data/cold/` and moves eligible data
    to Archive.
-   Rule C applies to a particular prefix and deletes eligible temporary
    data.

### How does Azure resolve conflicting actions?

When multiple lifecycle actions are eligible for the same blob in the
same evaluation, Azure applies the action with the least expensive
outcome for the blob. The precedence is generally:

1.  Delete
2.  Archive
3.  Cold
4.  Cool

This is not a rule-priority setting and does not mean every rule is
executed in sequence. Avoid designing conflicting rules. Use filters and
conditions so that each blob has one intended outcome.

**Production recommendation:** Make lifecycle rules mutually exclusive
where possible. Keep a clear naming convention and document the
container/prefix each rule targets.

## 5. Understand containers and virtual folders

Blob Storage uses blob names. A folder-like path is commonly a prefix in
the blob name, not a separate physical directory in a flat-namespace
account.

Example container: `company-data`

Example blob names:

``` text
logs/app-01.txt
logs/app-02.txt
cold/database-backup.bak
reports/annual-report.pdf
temporary/test-output.txt
```

Lifecycle prefix filters include the container name:

  Intended scope           `prefixMatch` value
  ------------------------ -------------------------
  All blobs in container   `company-data/`
  Logs virtual folder      `company-data/logs/`
  Cold virtual folder      `company-data/cold/`
  Reports virtual folder   `company-data/reports/`

A policy can also use an empty or omitted prefix filter to apply more
broadly, subject to the rule's other filters.

------------------------------------------------------------------------

# Practical Lab -- Advanced Lifecycle Management

## 6. Prerequisites

-   Azure subscription
-   Azure CLI installed
-   Linux, Ubuntu, or WSL terminal
-   Permission to create a StorageV2 account and management policy
-   `Storage Blob Data Contributor` for Entra ID-based blob uploads and
    listings
-   Permission to enable storage account data-management settings

Check Azure CLI:

``` bash
az version
```

## 7. Sign in and set variables

``` bash
az login
az account show --output table
```

If required, select a subscription:

``` bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

Define lab variables:

``` bash
RG="rg-advanced-lifecycle-demo"
LOCATION="centralindia"
STG="stgadvlife$(date +%s)"
CONTAINER="company-data"

echo "$STG"
```

Storage account names must be globally unique, lowercase, and 3--24
characters.

## 8. Create the resource group and Storage Account

``` bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

Create a General Purpose v2 account:

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

## 9. Assign blob data access and create the container

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

Allow time for role assignment propagation.

Create the container:

``` bash
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STG" \
  --auth-mode login
```

## 10. Upload sample files in different virtual folders

``` bash
mkdir -p lifecycle-advanced/logs lifecycle-advanced/cold lifecycle-advanced/reports lifecycle-advanced/temporary

echo "Application log one" > lifecycle-advanced/logs/app-01.txt
echo "Application log two" > lifecycle-advanced/logs/app-02.txt
echo "Database backup" > lifecycle-advanced/cold/database-backup.txt
echo "Annual report" > lifecycle-advanced/reports/annual-report.txt
echo "Temporary output" > lifecycle-advanced/temporary/test-output.txt
```

Upload the files:

``` bash
az storage blob upload-batch \
  --account-name "$STG" \
  --destination "$CONTAINER" \
  --source lifecycle-advanced \
  --auth-mode login \
  --tier Hot
```

List the blobs:

``` bash
az storage blob list \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --auth-mode login \
  --output table
```

## 11. Enable blob access-time tracking

By default, a storage account may not have blob access-time tracking
enabled. To use last-access-based lifecycle conditions, enable it.

``` bash
az storage account blob-service-properties update \
  --account-name "$STG" \
  --resource-group "$RG" \
  --enable-last-access-tracking true
```

Verify:

``` bash
az storage account blob-service-properties show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --query "{LastAccessTracking:automaticSnapshotPolicyEnabled,BlobService:blobServices}" \
  --output json
```

For a direct check of the access-time tracking property, inspect the
full output:

``` bash
az storage account blob-service-properties show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --output json
```

Look for `lastAccessTimeTrackingPolicy` and its `enable` property.

**Important access-time tracking notes:**

-   Last access is not updated synchronously on every read.
-   Azure uses a tracking policy and may update the recorded time at
    most once within a 24-hour period for a blob.
-   Access-time tracking can incur additional transaction charges.
-   The tracked timestamp is used by lifecycle evaluation; it is not a
    real-time event stream.
-   Confirm the current account support and billing details in Microsoft
    documentation.

## 12. Policy example A -- Move logs to Cool after 30 days

Create `policy-cool-logs.json`:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "MoveLogsToCool",
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
            }
          }
        }
      }
    }
  ]
}
```

Apply:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @policy-cool-logs.json
```

This rule only targets block blobs whose names begin with
`company-data/logs/`. It moves eligible blobs to Cool when the
last-modified age condition is satisfied.

## 13. Policy example B -- Use last access time

Create `policy-last-access.json`:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "MoveColdFolderAfterNoAccess",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/cold/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCold": {
              "daysAfterLastAccessTimeGreaterThan": 30
            }
          }
        }
      }
    }
  ]
}
```

Apply:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @policy-last-access.json
```

This is a separate example policy. Applying it replaces the storage
account's existing management policy; it does not append a rule to the
previous policy. To retain multiple rules, combine them into one JSON
document's `rules` array.

## 14. Policy example C -- Enable automatic tiering from Cool to Hot

The following illustrates the automatic re-tiering action for a Cool
blob when access tracking indicates that it has been accessed.

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "AutoTierCoolToHot",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/logs/"]
        },
        "actions": {
          "baseBlob": {
            "enableAutoTierToHotFromCool": true
          }
        }
      }
    }
  ]
}
```

Check the current lifecycle policy schema and action requirements before
applying. This action is designed for supported Cool-tier blobs and
relies on access-time tracking. It is not a generic instruction to move
every blob to Hot.

## 15. Policy example D -- Manage previous versions

If blob versioning is enabled, lifecycle rules can manage previous
versions.

Illustrative example:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "DeleteOldVersions",
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
          }
        }
      }
    }
  ]
}
```

This is a separate policy example. It targets previous versions, not the
current base blob. Enable blob versioning first and validate the policy
against the account's configuration.

## 16. Combine multiple rules in one policy

A storage account has one lifecycle management policy document
containing an array of rules. To keep several rules active, combine them
in that array.

Create `advanced-lifecycle-policy.json`:

``` json
{
  "rules": [
    {
      "enabled": true,
      "name": "MoveLogsToCool",
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
            "enableAutoTierToHotFromCool": true
          }
        }
      }
    },
    {
      "enabled": true,
      "name": "MoveColdFolderToArchive",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/cold/"]
        },
        "actions": {
          "baseBlob": {
            "tierToArchive": {
              "daysAfterLastAccessTimeGreaterThan": 180
            }
          }
        }
      }
    },
    {
      "enabled": true,
      "name": "DeleteTemporaryFiles",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["company-data/temporary/"]
        },
        "actions": {
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": 30
            }
          }
        }
      }
    }
  ]
}
```

Apply the combined policy:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @advanced-lifecycle-policy.json
```

**Read this carefully:** This is a teaching example showing how several
rules can coexist in one policy. Before production use, verify that each
action combination is supported by the current policy schema. In
particular, validate the automatic Cool-to-Hot action and its
interaction with other tiering actions. The rules use separate prefixes
to avoid unintended overlap.

## 17. Understand overlapping rules

Suppose two or more rules match the same blob and multiple actions
become eligible during the same evaluation.

Azure resolves competing actions using its documented action precedence.
In general, deletion takes precedence over tiering, and among tiering
actions the colder tier takes precedence over a warmer tier.

A useful teaching order is:

``` text
Delete
  |
Archive
  |
Cold
  |
Cool
```

Do not treat this as a configurable rule priority or as a sequence in
which every action executes. Design filters to avoid conflicting
outcomes and consult the current Microsoft documentation for exact
precedence behavior.

## 18. Inspect the active policy

``` bash
az storage account management-policy show \
  --account-name "$STG" \
  --resource-group "$RG" \
  --output json
```

You can also inspect the policy in Azure Portal:

1.  Open the Storage Account.
2.  Under **Data management**, select **Lifecycle management**.
3.  Review the rules list.
4.  Select a rule to inspect its filters, conditions, and actions.
5.  Open **Code view** to inspect the JSON.
6.  Add, edit, disable, or delete rules as required.

## 19. Test access tracking

Read a blob to create an access event:

``` bash
az storage blob download \
  --account-name "$STG" \
  --container-name "$CONTAINER" \
  --name "cold/database-backup.txt" \
  --file database-backup-downloaded.txt \
  --auth-mode login
```

A read does not change the blob's last-modified time. Access-time
tracking is updated asynchronously and is subject to its tracking
interval. Do not expect the recorded access time or a lifecycle action
to change immediately after this command.

## 20. Disable a rule or remove the policy

To disable a particular rule, edit its JSON and set:

``` json
"enabled": false
```

Then submit the complete policy document again:

``` bash
az storage account management-policy create \
  --account-name "$STG" \
  --resource-group "$RG" \
  --policy @advanced-lifecycle-policy.json
```

To remove the entire lifecycle policy:

``` bash
az storage account management-policy delete \
  --account-name "$STG" \
  --resource-group "$RG"
```

The delete command removes the whole management policy, not just one
rule.

## 21. Student assignment

-   [ ] Create a StorageV2 account and a container named `student-data`.
-   [ ] Upload files under `logs/`, `cold/`, `reports/`, and
    `temporary/`.
-   [ ] Create a rule that targets only `student-data/logs/`.
-   [ ] Create a second rule that targets only `student-data/cold/`.
-   [ ] Enable last-access-time tracking.
-   [ ] Create a rule using `daysAfterLastAccessTimeGreaterThan`.
-   [ ] Create a rule that deletes eligible temporary files.
-   [ ] Enable blob versioning and create a version-retention rule.
-   [ ] Combine at least three rules into one JSON policy.
-   [ ] Inspect the policy using Azure Portal Code view.
-   [ ] Explain what happens when two rules target the same blob.
-   [ ] Explain why a read does not necessarily update last-modified
    time.

## 22. Interview questions

1.  What is the purpose of Azure Blob Lifecycle Management?
2.  Can a storage account have multiple lifecycle rules?
3.  Can multiple rules apply to the same blob?
4.  How does Azure resolve competing lifecycle actions?
5.  What is `prefixMatch`?
6.  What is the difference between a container and a virtual folder in
    Blob Storage?
7.  What is the difference between last modified time and last access
    time?
8.  How do you enable blob access-time tracking?
9.  What does `enableAutoTierToHotFromCool` do?
10. Can lifecycle rules manage previous versions?
11. Does lifecycle management execute immediately?
12. Does lifecycle management rehydrate archived blobs?

## 23. Cleanup

Delete the lab resource group after completing the exercise:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

This removes the Storage Account and all resources in the resource
group.

## 24. Official Microsoft documentation

-   [Lifecycle management
    overview](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
-   [Lifecycle policy
    structure](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-structure)
-   [Lifecycle policy access-tier
    actions](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-access-tiers)
-   [Blob access-time
    tracking](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-access-time-tracking)
-   [Blob
    versioning](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview)

------------------------------------------------------------------------

## Chapter outcome

By the end of this chapter, students should be able to design advanced
JSON lifecycle policies, combine multiple rules, scope policies to
containers and virtual folders, use last-access-time conditions, enable
automatic Cool-to-Hot tiering where supported, manage blob versions, and
reason about overlapping actions.
