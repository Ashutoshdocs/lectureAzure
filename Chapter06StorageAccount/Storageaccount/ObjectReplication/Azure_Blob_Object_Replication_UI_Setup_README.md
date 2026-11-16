# Azure Blob Storage Object Replication --- UI-Based Setup

## Hands-on Lab Using Azure Portal

**Goal:** Configure Azure Blob Object Replication between two Storage
Accounts using only the Azure Portal, then upload files to the source
and verify that they appear in the destination.

**Example architecture:**

-   Source Storage Account: `stgsource...` --- East US
-   Destination Storage Account: `stgdest...` --- North Europe
-   Source container: `data-v1`
-   Destination container: `data-v1`

Object Replication asynchronously copies supported block blobs from a
source Storage Account to a destination Storage Account. It is useful
for maintaining a second regional copy of data or placing data closer to
users in another region.

> Replication is asynchronous. Do not expect a newly uploaded blob to
> appear in the destination instantly. The time taken can vary.

------------------------------------------------------------------------

## 1. What you will learn

By completing this lab, you will be able to:

1.  Create source and destination Storage Accounts.
2.  Enable Blob Versioning on both accounts.
3.  Enable Blob Change Feed on the source account.
4.  Create matching containers in both accounts.
5.  Configure an Object Replication rule.
6.  Upload new blobs to the source account.
7.  Verify that the blobs are asynchronously replicated to the
    destination.
8.  Understand how to configure replication for existing blobs, where
    supported.

## 2. Understand the architecture

```{=html}
<details>
```
```{=html}
<summary>
```
Object Replication flow
```{=html}
</summary>
```
``` text
                 SOURCE REGION
             East US Storage Account
              stgsourcexxxx
                     |
                     |
              Container: data-v1
                     |
             Upload block blobs
                     |
                     v
             Blob Change Feed
                     |
             Object Replication
                  Rule
                     |
              Asynchronous copy
                     |
                     v
                DESTINATION
           North Europe Storage Account
               stgdestxxxx
                     |
                     |
              Container: data-v1
                     |
              Replicated blobs
```

```{=html}
</details>
```
**Important:** The source and destination are separate Storage Accounts.
Object Replication is configured by creating a replication policy/rule
that maps a source container to a destination container.

## 3. Prerequisites

Before configuring Object Replication, check the following:

-   Use supported general-purpose v2 Storage Accounts.
-   The source and destination must support Blob Versioning.
-   Enable Blob Versioning on both accounts.
-   Enable Blob Change Feed on the source account.
-   Create the destination container before creating the rule.
-   Use supported block blobs.
-   Confirm that the account configuration and region combination meet
    the current Azure Object Replication requirements.

For this lab, use standard StorageV2 accounts and keep hierarchical
namespace (ADLS Gen2) disabled. Object Replication has feature and
account-configuration limitations; check the current Microsoft
documentation before using it with special account configurations.

## 4. Create the source Storage Account

### Step 1 --- Open Azure Portal

1.  Sign in to <https://portal.azure.com>.

2.  Search for **Storage accounts**.

3.  Select **Create**.

4.  Choose your subscription.

5.  Select an existing Resource Group or create a new one, for example:

    `rg-object-replication-lab`

6.  Enter a globally unique Storage Account name, for example:

    `stgsource<unique-number>`

    Storage Account names must be lowercase letters and numbers, 3--24
    characters, and globally unique.

7.  Select the source region, for example **East US**.

8.  Select **Standard** performance.

9.  Select **Locally-redundant storage (LRS)** for this simple
    demonstration.

10. Choose **StorageV2 (general purpose v2)** as the account type, if
    shown.

11. Keep **Hierarchical namespace** disabled.

12. Select **Review** and then **Create**.

Wait for deployment to complete, then open the Storage Account.

## 5. Enable Blob Versioning on the source

1.  Open the source Storage Account.
2.  Under **Data management**, select **Data protection**.
3.  Find the **Tracking** or **Blob versioning** section (the exact
    portal grouping may change).
4.  Enable **Enable versioning for blobs**.
5.  Select **Save**.

Why is this required?

Object Replication uses blob versions to replicate changes. Blob
Versioning must be enabled on both the source and destination accounts.

## 6. Enable Blob Change Feed on the source

Remain in the source Storage Account:

1.  Open **Data management → Data protection**.
2.  Find **Enable blob change feed**.
3.  Turn it on.
4.  If the portal asks how long to retain change feed logs, choose an
    appropriate retention period for the lab, such as **7 days**, if
    available.
5.  Select **Save**.

**What is Change Feed?**

Blob Change Feed provides a durable, ordered log of changes to blobs.
Object Replication uses this change information to identify changes that
need to be replicated from the source.

For a production environment, choose a retention configuration that
meets the workload and operational requirements. Do not treat the change
feed retention setting as a substitute for a data-retention or backup
policy.

## 7. Create the destination Storage Account

1.  Return to **Storage accounts**.

2.  Select **Create**.

3.  Select the same subscription.

4.  Select the lab Resource Group, for example
    `rg-object-replication-lab`.

5.  Enter another globally unique name, for example:

    `stgdest<unique-number>`

6.  Choose a different region, for example **North Europe**.

7.  Select **Standard** performance.

8.  Select **Locally-redundant storage (LRS)** for the lab.

9.  Use **StorageV2 (general purpose v2)**.

10. Keep **Hierarchical namespace** disabled.

11. Select **Review + create**, then **Create**.

12. Open the destination Storage Account after deployment.

### Enable Blob Versioning on the destination

1.  In the destination Storage Account, open **Data management → Data
    protection**.
2.  Enable **Blob versioning**.
3.  Select **Save**.

**Check before proceeding:** Blob Versioning should now be enabled on
both source and destination accounts. Blob Change Feed should be enabled
on the source account.

## 8. Create matching containers

Object Replication needs a destination container to receive the
replicated blobs.

### Create the source container

1.  Open the source Storage Account.

2.  Select **Data storage → Containers**.

3.  Select **+ Container**.

4.  Enter the name:

    `data-v1`

5.  Keep the access level **Private (no anonymous access)**.

6.  Select **Create**.

### Create the destination container

1.  Open the destination Storage Account.

2.  Select **Data storage → Containers**.

3.  Select **+ Container**.

4.  Enter the same name:

    `data-v1`

5.  Keep the access level **Private (no anonymous access)**.

6.  Select **Create**.

The source and destination container names in this example are
identical. The rule can map a source container to a destination
container according to the options available in the portal.

## 9. Configure Object Replication

Now configure the replication rule from the **source Storage Account**.

1.  Open the source Storage Account.

2.  In the left navigation, locate **Data management → Object
    replication**.

3.  Select **Create replication rules** or **Add rule**.

4.  Give the replication policy a meaningful name, for example:

    `replicate-eastus-to-northeurope`

5.  Select the destination subscription, if requested.

6.  Select the destination Storage Account:

    `stgdest<unique-number>`

7.  Select the source container:

    `data-v1`

8.  Select the destination container:

    `data-v1`

9.  Review the option for replicating existing blobs.

    -   For the first demonstration, choose the option to replicate
        **new objects only**, if the portal presents that choice.
    -   If you need to copy eligible blobs that already exist in the
        source, select the option for existing blobs where available and
        review its requirements and limitations.

10. Review the source-to-destination mapping.

11. Select **Create** or **Save**.

The portal creates the replication policy/rule. If the destination
account requires approval or confirmation, complete the prompt shown in
the portal.

**Important:** The portal wording and available options can vary. Follow
the options displayed for your account and region. Existing-blob
replication can have additional requirements; do not assume that
selecting a rule automatically backfills every historical blob.

## 10. Upload test files to the source

1.  Open the source Storage Account.
2.  Select **Containers**.
3.  Open `data-v1`.
4.  Select **Upload**.
5.  Select one or more local files, such as:
    -   `demo.txt`
    -   `config.json`
    -   `sample.pdf`
6.  Select **Upload**.

You have now uploaded the files to the source container.

**Expected result:** The files are visible in the source container.
Object Replication processes the eligible changes asynchronously.

## 11. Verify replication in the destination

1.  Open the destination Storage Account.
2.  Select **Containers**.
3.  Open `data-v1`.
4.  Refresh the container listing after a short wait.
5.  Check whether the uploaded blobs appear.

If the objects do not appear immediately:

-   Wait and refresh again.
-   Confirm that the replication rule is enabled and maps the intended
    source and destination containers.
-   Confirm Blob Versioning is enabled on both accounts.
-   Confirm Blob Change Feed is enabled on the source.
-   Check that you uploaded supported block blobs after the rule was
    created, if the rule is configured for new objects only.
-   Inspect the replication status or rule details in the portal, if
    available.

Do not interpret a short delay as a failure: Object Replication is
asynchronous and does not promise immediate copying.

## 12. Test an update to an existing blob

This test demonstrates that replication is not limited to the first
upload.

1.  Open the source container `data-v1`.
2.  Select `demo.txt` (or another test block blob).
3.  Download it and change its content locally.
4.  Upload the modified file using the same blob name, replacing the
    current blob.
5.  Wait for asynchronous replication.
6.  Open the destination container and inspect the replicated blob.

Depending on the rule and supported operation, the updated blob content
should be replicated. Use the replication status and current Microsoft
documentation to understand the state of a particular blob.

## 13. Understand replication status

Azure exposes replication-related status information for blobs and
rules. The exact fields and where they appear can vary by portal
experience.

Common concepts include:

-   **Policy / rule:** Defines which source container maps to which
    destination container.
-   **Pending:** A replication operation is still being processed.
-   **Complete:** The relevant replication operation has completed.
-   **Failed:** The operation did not complete successfully and needs
    investigation.

If the portal exposes a replication status for a blob, use it rather
than relying only on the presence of a filename in the destination.

## 14. Troubleshooting checklist

  -----------------------------------------------------------------------
  Symptom                             What to check
  ----------------------------------- -----------------------------------
  Cannot create a rule                Check supported account types,
                                      versioning, permissions, and
                                      destination selection

  Rule cannot be saved                Confirm source and destination
                                      containers exist and account
                                      prerequisites are met

  Blob does not appear in destination Confirm rule mapping, enabled
                                      state, supported blob type, and
                                      asynchronous delay

  New uploads replicate but older     Check whether the rule is
  files do not                        configured for new objects only

  Replication is not progressing      Inspect rule/blob status, account
                                      settings, and current Azure service
                                      limitations

  Authorization error                 Check permissions on both Storage
                                      Accounts and the required
                                      data-plane access

  Destination container is missing    Create the destination container
                                      and verify the mapping
  -----------------------------------------------------------------------

## 15. Important production considerations

### Object Replication is asynchronous

It is not a synchronous write to two accounts. An application should not
assume that a blob is immediately available in the destination after
upload to the source.

### Replication is not the same as backup

Object Replication copies supported block blobs to another account. It
is useful for regional distribution and additional copies, but it is not
by itself a complete backup or disaster-recovery strategy.

Consider:

-   Separate protection against accidental deletion.
-   Retention and recovery requirements.
-   Access control and account-level security.
-   Monitoring and alerting for replication failures or delays.
-   Whether the destination copy meets the recovery-point and
    recovery-time objectives.

### Cost considerations

You can incur costs for:

-   Storage in both accounts.
-   Replication transactions.
-   Data transfer, including inter-region transfer charges where
    applicable.
-   Retained versions and change feed data.

Review current Azure pricing for the selected regions, redundancy, and
workload.

## 16. Student assignment

Complete these tasks in the Azure Portal:

1.  Create a source Storage Account in one region.
2.  Create a destination Storage Account in another region.
3.  Enable Blob Versioning on both accounts.
4.  Enable Blob Change Feed on the source account.
5.  Create a private container named `training-data` in both accounts.
6.  Create an Object Replication rule mapping the source container to
    the destination container.
7.  Configure the rule for new objects only.
8.  Upload three block blobs to the source container.
9.  Verify that the blobs appear in the destination after replication.
10. Modify one source blob and verify the result.
11. Explain why replication is asynchronous.
12. Explain why Object Replication alone should not be treated as a
    complete backup strategy.

## 17. Interview questions

1.  What is Azure Blob Object Replication?
2.  Is Object Replication synchronous or asynchronous?
3.  Which blob type is supported by Object Replication?
4.  What is Blob Change Feed, and why is it required?
5.  Why must Blob Versioning be enabled on both accounts?
6.  Can the source and destination Storage Accounts be in different
    Azure regions?
7.  What is the purpose of a replication rule?
8.  What is the difference between replicating new blobs and existing
    blobs?
9.  Does Object Replication replace Azure Backup or a complete
    disaster-recovery strategy?
10. What cost factors should be considered when enabling cross-region
    replication?

## 18. Cleanup

When the lab is complete:

1.  Open the source Storage Account's **Object replication** page.
2.  Remove the replication policy/rule if you no longer need it,
    following the portal prompts.
3.  Confirm that no other workload depends on the Storage Accounts.
4.  Delete the lab Resource Group only if it contains lab resources
    exclusively.

Deleting the Resource Group permanently deletes both Storage Accounts
and their data. Never perform cleanup against a shared or production
Resource Group.

------------------------------------------------------------------------

## Official Microsoft documentation

-   [Object replication for block
    blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/object-replication-overview)
-   [Configure object
    replication](https://learn.microsoft.com/en-us/azure/storage/blobs/object-replication-configure)
-   [Blob
    versioning](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview)
-   [Blob change
    feed](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-change-feed)

**Trainer's summary:** Create two supported Storage Accounts, enable
Blob Versioning on both, enable Change Feed on the source, create
matching containers, configure the source-to-destination replication
rule, and upload test block blobs. Azure then copies eligible changes
asynchronously to the destination.
