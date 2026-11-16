# Azure Premium Storage Accounts --- Premium Block Blob Practical

## Hands-on Lab Using Azure Portal

**Goal:** Create a Premium Block Blob Storage Account, upload a blob,
inspect the available features, compare it with a General-purpose v2
account, and understand the performance and cost trade-offs.

**Audience:** Azure beginners, administrators, and cloud/DevOps
learners\
**Estimated time:** 30--45 minutes

------------------------------------------------------------------------

## 1. Learning objectives

By the end of this practical, you will be able to:

-   Explain the difference between a General-purpose v2 Storage Account
    and a Premium Block Blob account.
-   Create a Premium Block Blob Storage Account using Azure Portal.
-   Create a private container and upload a block blob.
-   Inspect blob properties and available access-tier options.
-   Understand why Hot, Cool, Cold, and Archive tiers are not available
    for Premium Block Blob accounts.
-   Explore the lifecycle management capabilities available for the
    account.
-   Identify when Premium Block Blob or Premium Azure Files is a better
    fit.

## 2. What is Premium Storage?

Azure Storage offers different account types for different workloads.

A **Standard General-purpose v2 (GPv2)** Storage Account provides access
to multiple storage services, including:

-   Blob Storage
-   Azure Files
-   Queues
-   Tables

A **Premium Block Blob** account is designed for workloads that need
high transaction performance and low latency for block blob operations.
It uses premium storage infrastructure and is intended for
performance-sensitive workloads.

Examples of workloads that may benefit include:

-   Applications with frequent, latency-sensitive blob reads and writes.
-   Interactive content or media workflows with demanding performance
    needs.
-   Data ingestion workloads that generate many blob operations.
-   Applications where predictable high transaction performance is more
    important than low storage cost.

Premium storage generally has a higher storage price than Standard
storage. However, transaction pricing and performance characteristics
differ by account type and region. Compare the complete workload cost
rather than assuming Premium is always cheaper or always faster for
every operation.

## 3. Premium account types

Azure has different premium storage options. They are not one account
that enables every storage service.

  -----------------------------------------------------------------------
  Premium option          Storage service         Typical use
  ----------------------- ----------------------- -----------------------
  Premium Block Blob      Block blobs             High-performance blob
                                                  workloads

  Premium File Shares     Azure Files             Low-latency,
                                                  high-performance file
                                                  shares

  Premium Page Blobs      Page blobs / unmanaged  Specialized page-blob
                          disk scenarios          workloads
  -----------------------------------------------------------------------

**Important:** A Premium Block Blob account is not the same as a Premium
File Share account. Choose the premium account type that matches the
storage service your application needs.

## 4. Standard GPv2 vs Premium Block Blob

  -----------------------------------------------------------------------
  Feature                 Standard GPv2           Premium Block Blob
  ----------------------- ----------------------- -----------------------
  Main purpose            General-purpose storage Performance-sensitive
                                                  block blob workloads

  Blob service            Yes                     Yes

  Azure Files             Yes                     No

  Queues                  Yes                     No

  Tables                  Yes                     No

  Blob access tiers       Hot, Cool, Cold,        No
                          Archive, subject to     Hot/Cool/Cold/Archive
                          account/blob            tier selection
                          eligibility             

  Storage performance     Standard                Premium

  Cost profile            Lower storage cost in   Higher storage cost;
                          many scenarios;         transaction pricing
                          transaction charges     differs
                          depend on tier and      
                          operation               

  Best fit                General-purpose         Low-latency,
                          applications and mixed  high-transaction block
                          storage services        blob workloads
  -----------------------------------------------------------------------

The exact redundancy choices and feature availability depend on region,
account configuration, and current Azure support.

## 5. Prerequisites

-   An Azure subscription.
-   Permission to create Storage Accounts.
-   Azure Portal access: <https://portal.azure.com>
-   A Resource Group for the lab.

For this example, we will create:

-   Resource Group: `rg-premium-storage-lab`
-   Account name: `stpremblob<unique-number>`
-   Account type: Premium Block Blob
-   Container: `premium-demo`

Storage Account names must be globally unique, lowercase, and 3--24
characters long.

## 6. Create a Resource Group

1.  Sign in to the Azure Portal.

2.  Search for **Resource groups**.

3.  Select **Create**.

4.  Choose your subscription.

5.  Enter:

    `rg-premium-storage-lab`

6.  Select a region, for example **Central India**.

7.  Select **Review + create**.

8.  Select **Create**.

## 7. Create a Premium Block Blob Storage Account

1.  Search for **Storage accounts**.

2.  Select **Create**.

3.  Choose your subscription.

4.  Select the Resource Group:

    `rg-premium-storage-lab`

5.  Enter a globally unique Storage Account name, for example:

    `stpremblob<unique-number>`

6.  Select the region where the required premium redundancy option is
    available.

7.  In **Performance**, select **Premium**.

8.  In **Premium account type**, select **Block blobs** (the exact
    wording may vary in the Portal).

9.  Review the redundancy choices shown for the selected region. Premium
    Block Blob accounts commonly offer a more limited set of redundancy
    options than Standard GPv2; select an option supported in your
    region and appropriate for the lab.

10. Keep **Hierarchical namespace** disabled for this practical unless
    your specific scenario requires and supports it.

11. Review the **Networking**, **Data protection**, and **Encryption**
    tabs.

12. Keep public access disabled at the container level. Restrict network
    access according to your lab requirements.

13. Select **Review + create**.

14. Review the account configuration.

15. Select **Create**.

Wait for deployment to finish, then select **Go to resource**.

**Trainer note:** The Portal only shows account types and redundancy
options supported by the chosen region and configuration. If Premium
Block Blob is not available in the selected region, choose a supported
region rather than changing to a different account type without
understanding the difference.

## 8. Explore the Storage Account services

Open the new Premium Block Blob Storage Account.

Under **Data storage**, inspect the available navigation items.

For a Premium Block Blob account, the primary data service is Blob
Storage. You should not expect the full set of GPv2 services such as
Azure Files, Queues, and Tables to be available in this account.

**Teaching point:** Premium Block Blob is a specialized account type. If
your application also needs Azure Files, Queues, or Tables, evaluate
whether those services should live in a separate Standard GPv2 account
or an appropriate premium account.

## 9. Create a container

1.  In the Storage Account, open **Data storage → Containers**.

2.  Select **+ Container**.

3.  Enter:

    `premium-demo`

4.  Set **Anonymous access level** to **Private (no anonymous access)**.

5.  Select **Create**.

6.  Open the `premium-demo` container.

## 10. Upload a test block blob

1.  Inside the `premium-demo` container, select **Upload**.
2.  Select a local file, for example `sample.txt`, `sample.pdf`, or an
    image.
3.  Leave the blob type as **Block blob** if the Portal asks.
4.  Select **Upload**.
5.  Wait for the upload to finish.
6.  Verify that the blob appears in the container.

To create a simple test file on your computer, you can use a text editor
and save:

``` text
This file is stored in an Azure Premium Block Blob account.
```

as `sample.txt`.

## 11. Inspect the blob properties

1.  Select the uploaded blob.
2.  Inspect its **Properties**.
3.  Review information such as:
    -   Blob name
    -   URL
    -   Last modified time
    -   Blob type
    -   Size
    -   ETag
    -   Content type

The properties page helps you understand the object stored in the
account.

## 12. Inspect access tiers

In a Standard GPv2 account, eligible block blobs can use access tiers
such as:

-   Hot
-   Cool
-   Cold
-   Archive

Now inspect the uploaded blob in the Premium Block Blob account.

1.  Select the blob.
2.  Look for **Change tier** or the access-tier field.
3.  Notice that the Standard Hot/Cool/Cold/Archive access-tier workflow
    is not available for Premium Block Blob accounts.

**Why?**

Premium Block Blob accounts are provisioned for performance rather than
using the Standard blob access-tier model. You cannot treat a Premium
Block Blob account as a Standard account with a Hot tier. If you need
Hot, Cool, Cold, or Archive lifecycle tiering, use an eligible Standard
GPv2 account.

## 13. Explore Lifecycle Management

Lifecycle Management can automate actions on eligible blobs, such as
moving data between supported access tiers or deleting data after a
retention period.

In the Premium Block Blob account:

1.  Open the Storage Account.

2.  Under **Data management**, select **Lifecycle management**.

3.  Select **Add a rule**.

4.  Enter a rule name, for example:

    `delete-old-premium-blobs`

5.  Choose the scope/filter options available in the Portal.

6.  Configure a last-modified condition, for example a test condition
    for blobs older than a chosen number of days.

7.  Inspect the available actions.

For Premium Block Blob accounts, do not expect the Standard
Hot/Cool/Cold/Archive tier transition workflow. Depending on the current
account and Portal capabilities, delete actions may be available while
tier-transition actions are not.

**Important lab safety:** Do not enable a broad delete rule on an
account containing important data. If you test a delete policy, use a
dedicated lab container and a deliberately short retention period only
after understanding that lifecycle policies are asynchronous and
deletion can be permanent depending on your protection settings.

8.  Save the rule only if you intend to test it.
9.  For a learning-only inspection, cancel or remove the unsaved rule.

Lifecycle rules are evaluated periodically, not immediately after you
save them. Do not expect an object to be deleted at the exact moment its
age condition is met.

## 14. Optional comparison --- Create a Standard GPv2 account

To see the difference directly, create a second Storage Account.

1.  Search for **Storage accounts**.
2.  Select **Create**.
3.  Choose the same Resource Group.
4.  Enter a unique name, for example `ststdblob<unique-number>`.
5.  Select the same region where possible.
6.  Select **Standard** performance.
7.  Select **StorageV2 (general purpose v2)**.
8.  Select a supported redundancy option.
9.  Review and create the account.
10. Create a private container named `standard-demo`.
11. Upload a test block blob.
12. Open the blob and inspect the **Change tier** option.

In the Standard GPv2 account, eligible block blobs can use the supported
access tiers. Availability depends on the account, blob type, region,
and other conditions.

## 15. When should you choose Premium Block Blob?

Choose Premium Block Blob when:

-   The workload is block-blob based.
-   The workload is sensitive to latency.
-   The application performs frequent blob transactions.
-   Performance requirements justify the higher storage price.
-   You do not require Standard blob access tiers for the data in that
    account.

Choose Standard GPv2 when:

-   You need a general-purpose Storage Account.
-   You need Blob Storage plus Azure Files, Queues, or Tables in the
    same account.
-   You need Hot, Cool, Cold, or Archive access-tier capabilities for
    eligible blobs.
-   Cost-efficient storage for mixed workloads is a priority.

Choose Premium File Shares when the requirement is a high-performance
Azure Files share, rather than premium block blob storage.

## 16. Cost considerations

Do not compare only the per-GB storage price.

Evaluate:

-   Capacity consumed.
-   Read, write, and list transactions.
-   Data retrieval and data transfer.
-   Redundancy option.
-   Region.
-   Workload request pattern.
-   Provisioning and performance requirements.
-   Retention and protection features.

Premium storage can cost more per GB, but its transaction pricing and
performance model differ. Use the Azure Pricing Calculator and test with
representative workloads before choosing an account type for production.

Official pricing calculator:
<https://azure.microsoft.com/pricing/calculator/>

## 17. Student assignment

1.  Create a Premium Block Blob Storage Account.
2.  Create a private container.
3.  Upload three test block blobs.
4.  Inspect their properties.
5.  Check whether the Hot/Cool/Cold/Archive tier selection is available.
6.  Open Lifecycle Management and inspect the actions available.
7.  Create a Standard GPv2 Storage Account.
8.  Upload the same test files to the Standard account.
9.  Compare the access-tier options.
10. Write a short recommendation for a company that needs low-latency
    blob access but also needs Azure Files and Queue Storage.

## 18. Interview questions

1.  What is a Premium Block Blob Storage Account?
2.  How is it different from Standard GPv2?
3.  Which storage service is provided by a Premium Block Blob account?
4.  Can you use Azure Files, Queues, and Tables in a Premium Block Blob
    account?
5.  Why are Hot, Cool, Cold, and Archive tiers not available for Premium
    Block Blob?
6.  What is the difference between Premium Block Blob and Premium File
    Shares?
7.  Does Premium storage always cost less overall?
8.  What factors should you evaluate before selecting Premium storage?
9.  Can Lifecycle Management still be useful in a Premium Block Blob
    account?
10. Why should you benchmark your workload before selecting a premium
    account?

## 19. Cleanup

1.  Confirm that the accounts contain only lab data.
2.  Open **Resource groups** in the Azure Portal.
3.  Select `rg-premium-storage-lab`.
4.  Select **Delete resource group**.
5.  Enter the Resource Group name to confirm.
6.  Select **Delete**.

This permanently deletes the lab Storage Accounts and their data. Never
delete a shared or production Resource Group.

------------------------------------------------------------------------

## Official Microsoft documentation

-   [Azure Storage account
    overview](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview)
-   [Premium block blob
    accounts](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-block-blob-premium)
-   [Azure Blob Storage access
    tiers](https://learn.microsoft.com/en-us/azure/storage/blobs/access-tiers-overview)
-   [Lifecycle management
    overview](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
-   [Azure Storage
    pricing](https://azure.microsoft.com/pricing/details/storage/)

**Trainer's closing explanation:** Standard GPv2 is the general-purpose
option with multiple storage services and blob access tiers. Premium
Block Blob is a specialized, performance-focused option for block blob
workloads. It is not simply a faster GPv2 account: it has a different
service and feature set, so select it only when the workload needs its
performance characteristics.
