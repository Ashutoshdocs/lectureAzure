# Azure Blob Storage -- Stored Access Policy & Immutable Storage Practical

**Practical type:** Azure Portal (UI-first)\
**Audience:** Azure beginners, administrators, and cloud engineers\
**Goal:** Learn how to centrally control a container-level shared access
signature (SAS) using a stored access policy, and how to protect blob
data from modification or deletion using immutable storage.

------------------------------------------------------------------------

# Part 1 -- Stored Access Policy

## 1. What is a Stored Access Policy?

A stored access policy is a policy defined on an Azure Blob Storage
container. A **service SAS** can refer to this policy by its identifier.
The policy centrally controls the SAS permissions and, where configured,
its start time, expiry time, and revocation behavior.

Without a stored access policy, the SAS permissions and validity period
are embedded directly in the SAS token. If you need to revoke an
individual ad hoc SAS, you generally need to rotate the account key used
to sign it, which can affect other SAS tokens signed with that key.

With a stored access policy, you can change or delete the policy to
affect service SAS tokens that reference it. Changes are not necessarily
instantaneous everywhere; allow for propagation and test the result.

### Important concepts

  -----------------------------------------------------------------------
  Term                                Meaning
  ----------------------------------- -----------------------------------
  SAS                                 A signed URI that grants limited
                                      access to storage resources

  Service SAS                         SAS for a specific storage service
                                      resource, such as a blob or
                                      container

  Stored access policy                A named policy on a container that
                                      a service SAS can reference

  Policy identifier                   The ID included when generating the
                                      SAS

  Permissions                         Operations such as read, write,
                                      delete, and list

  Expiry                              The date/time after which access is
                                      no longer valid
  -----------------------------------------------------------------------

**Scope note:** Stored access policies apply to service SAS tokens for
supported Blob Storage resources. They do not govern account SAS tokens
or user delegation SAS tokens.

## 2. Architecture

``` text
Client / User
     |
     | Service SAS URL
     | (includes signed identifier)
     v
Azure Blob Container
     |
     +---- Stored Access Policy: ReadOnlyPolicy
                |
                +-- Permissions: Read + List
                +-- Start time: optional
                +-- Expiry time: configured
```

The SAS token references the policy identifier. Azure evaluates the
policy settings when the token is used.

## 3. Prerequisites

-   Azure subscription and permission to create a Storage Account.
-   Permission to manage the container and generate SAS tokens.
-   A standard StorageV2 (general-purpose v2) account for this lab.
-   A browser and Azure Portal access.

Use a lab-only account and sample data. Treat SAS URLs as passwords:
anyone who obtains a valid SAS URL may be able to use the permissions it
grants.

## 4. Create the Storage Account

1.  Sign in to the [Azure Portal](https://portal.azure.com).
2.  Search for **Storage accounts**.
3.  Select **Create**.
4.  On **Basics**, select:
    -   Subscription: your lab subscription.
    -   Resource group: create `rg-sas-immutable-demo`.
    -   Storage account name: `stsasimmutabledemo` (or a globally unique
        lowercase alternative).
    -   Region: your preferred lab region.
    -   Performance: **Standard**.
    -   Redundancy: **LRS** for a low-cost lab, if available.
5.  Keep account kind as **StorageV2 (general-purpose v2)**.
6.  Review networking and security options. Keep public access
    restricted according to your lab policy.
7.  Select **Review + create**, then **Create**.
8.  Open the deployed Storage Account.

## 5. Create a Container and Upload a Test Blob

1.  In the Storage Account, open **Data storage** → **Containers**.
2.  Select **+ Container**.
3.  Name it `sas-demo`.
4.  Keep **Anonymous access level** set to **Private (no anonymous
    access)**.
5.  Select **Create**.
6.  Open the `sas-demo` container.
7.  Create a local text file named `policy-demo.txt` with sample
    content:

``` text
Stored Access Policy Demonstration
This file is used to test a read-only service SAS.
```

8.  Select **Upload** and upload `policy-demo.txt`.

## 6. Create a Stored Access Policy

1.  Open the `sas-demo` container.
2.  Find **Access policy** in the container management menu. The exact
    portal navigation label may vary slightly.
3.  In the **Stored access policies** section, select **+ Add policy**.
4.  Enter:
    -   Identifier: `ReadOnlyPolicy`
    -   Permissions: **Read** and **List**
    -   Start time: leave blank for the classroom demo, unless your
        organization requires one.
    -   Expiry time: set a short future time, for example 2 hours from
        the time of the lab.
5.  Save the policy.

**Teaching note:** The stored policy is a named rule on the container.
It is not itself a SAS URL and does not automatically make the container
public.

## 7. Generate a Service SAS That References the Policy

The portal experience for SAS generation can vary. The key requirement
is that the generated **service SAS** references the stored access
policy identifier.

1.  Open the `sas-demo` container.
2.  Open **Shared access tokens** / **Generate SAS** for the container,
    where available.
3.  Select **Service SAS** (not Account SAS and not User delegation
    SAS).
4.  Select the stored access policy `ReadOnlyPolicy` as the signed
    identifier, if the portal exposes that field.
5.  Ensure the permissions are no broader than the policy allows. For
    this demo, use **Read** and **List** only.
6.  Generate the SAS token or URL.
7.  Copy it into a secure temporary location for testing. Do not paste
    it into public notes, screenshots, source control, or chat.

If the current portal workflow does not expose a stored-policy
identifier, generate the service SAS with a supported tool such as Azure
Storage Explorer or Azure CLI, selecting the policy identifier. Do not
mistake a SAS generated with explicit start/expiry/permissions and no
signed identifier for a stored-access-policy-backed SAS.

## 8. Test the SAS

Use a private/incognito browser window or a command-line HTTP client.

-   Open the blob SAS URL for `policy-demo.txt`. The read request should
    succeed.
-   Use the container SAS URL with list operation if you want to
    demonstrate listing.
-   Attempt a write or delete operation using the read-only SAS. It
    should be denied.

### Expected results

  -----------------------------------------------------------------------
  Test                                Expected outcome
  ----------------------------------- -----------------------------------
  Read `policy-demo.txt` with SAS     Allowed

  List container with SAS             Allowed, if the SAS is scoped for
                                      container listing

  Upload a new blob                   Denied

  Delete a blob                       Denied

  Access without SAS while container  Denied
  is private                          
  -----------------------------------------------------------------------

A SAS is a bearer token. Do not expose the full URL during a live stream
or record it in teaching screenshots.

## 9. Demonstrate Central Revocation or Change

1.  Return to the container's **Access policy** page.
2.  Edit `ReadOnlyPolicy` and shorten its expiry or remove the policy.
3.  Save the change.
4.  Retry the previously generated SAS URL.
5.  Confirm that the service SAS referencing that policy is no longer
    authorized after the policy change has propagated.

**Teaching note:** This is the key benefit. You can centrally change or
revoke access for service SAS tokens that reference the stored policy
without distributing a replacement URL to every client.

### Stored access policy limitations

-   A container supports a limited number of stored access policies
    (currently up to five per container).
-   Stored access policies are supported for service SAS, not account
    SAS or user delegation SAS.
-   A SAS token must include the signed identifier to be governed by the
    stored policy.
-   Changes may take time to propagate.
-   Do not rely on a stored access policy as a substitute for Microsoft
    Entra ID, RBAC, private networking, or secure secret handling.
-   If a SAS was created without referencing the policy, changing the
    policy will not control that SAS.

------------------------------------------------------------------------

# Part 2 -- Azure Immutable Blob Storage

## 10. What is Immutable Storage?

Azure Blob immutable storage provides Write Once, Read Many (WORM)
protection. Once a blob is protected by an applicable immutability
policy, it cannot be modified or deleted during the retention period,
subject to the policy type and permitted administrative operations.

It is designed for scenarios such as: - Regulatory and compliance
retention. - Audit records. - Financial records. - Legal evidence. -
Security logs that must not be altered or removed during a defined
period.

### Two main controls

  -----------------------------------------------------------------------
  Feature                             Purpose
  ----------------------------------- -----------------------------------
  Time-based retention policy         Protects data for a defined number
                                      of days

  Legal hold                          Keeps data immutable until the
                                      legal hold is explicitly cleared
  -----------------------------------------------------------------------

A time-based retention policy can be configured at the container level
or, where supported, at the individual blob version level. This
practical uses a container-level policy for a straightforward
demonstration.

## 11. Immutable Storage Architecture

``` text
Azure Storage Account
        |
        +---- Container: compliance-records
                    |
                    +---- audit-001.txt
                    +---- invoice-001.txt
                    +---- evidence-001.txt
                    |
                    +---- Immutability policy
                              |
                              +-- Time-based retention
                              |      Example: 7 days (lab only)
                              |
                              +-- OR Legal hold
                                     Tag: legal-case-001
```

**Important:** Immutable storage is not the same as soft delete, blob
versioning, snapshots, or backup. Those features serve different
recovery and retention purposes.

## 12. Create a Dedicated Container for the Immutability Demo

Use a separate container from the stored access policy exercise.

1.  Open the Storage Account.
2.  Select **Containers**.
3.  Select **+ Container**.
4.  Name it `compliance-records`.
5.  Keep anonymous access as **Private**.
6.  Create the container.
7.  Upload a sample file named `audit-record.txt` containing:

``` text
AUDIT RECORD
Record ID: AUDIT-001
Created for Azure immutable storage classroom demo.
This record must not be modified or deleted while protected.
```

**Why use a separate container?** It keeps the SAS lab and
immutable-storage lab independent and makes it easier to explain the
different controls.

## 13. Configure a Time-Based Retention Policy

1.  Open the `compliance-records` container.
2.  Locate **Immutable storage** / **Access policy** / **Immutability
    policy** in the container menu. Portal labels can change.
3.  Select the option to configure a **time-based retention policy**.
4.  For a disposable classroom demo, choose a short retention period
    such as **7 days**, if the portal allows it.
5.  Review whether the policy is created in a locked or unlocked state.
6.  For the first demonstration, keep the policy **unlocked** if the
    portal allows that state.
7.  Save the policy.

### Unlocked vs locked

-   **Unlocked policy:** An authorized administrator can change the
    retention duration or delete the policy, subject to Azure's rules.
-   **Locked policy:** The policy becomes much more restrictive. Its
    retention duration can generally be increased, but not shortened or
    removed before expiry. Locking is intended for compliance scenarios.

**Classroom safety rule:** Do not lock an immutable policy on a shared
or production container just to demonstrate it. A locked policy can
prevent deletion of protected data and may cause ongoing storage costs
until retention expires.

## 14. Test the Unlocked Policy

1.  Open the protected `audit-record.txt` blob.
2.  Attempt to overwrite it with a different file using the same name.
3.  Attempt to delete it.
4.  Observe the portal error message indicating that the operation is
    blocked by the immutability policy.
5.  Read or download the blob to show that read access remains
    available.

Expected behavior: - Read: allowed. - Overwrite: blocked while
protected. - Delete: blocked while protected.

The precise operations allowed can depend on policy scope, policy state,
blob type, versioning configuration, and the operation attempted. Use a
block blob for this practical.

## 15. Demonstrate Legal Hold (Optional)

A legal hold is different from a fixed retention duration. It remains in
effect until an authorized user clears the hold.

1.  Use a separate test container named `legal-hold-demo`.
2.  Upload `legal-evidence.txt`.
3.  Open the container's immutability settings.
4.  Add a legal hold.
5.  Add a tag such as `legal-case-001` if the portal asks for a tag.
6.  Save the legal hold.
7.  Attempt to overwrite or delete the protected blob.
8.  Confirm that the operation is blocked.
9.  For a disposable lab only, remove the legal hold after the
    demonstration and verify that the hold status is cleared.

**Important:** Do not apply legal holds to real business data as a
classroom exercise. Use only disposable demo data and follow
organizational/legal approval procedures.

## 16. Understand Policy Scope: Container vs Blob Version

Azure immutable storage has different configuration scopes:

-   **Container-level immutability:** Protects blobs in the container
    under the container's policy.
-   **Version-level immutability:** Protects individual blob versions
    when the relevant versioning and immutability capabilities are
    configured.

Do not assume that a policy at one scope behaves exactly like a policy
at the other. For production, confirm feature compatibility, account
configuration, and operational limits in Microsoft's current
documentation.

## 17. What Happens After the Retention Period?

For a time-based retention policy, the protected blob becomes eligible
for modification or deletion after the retention period has elapsed,
subject to the policy scope and any other protections.

Expiry does not automatically delete the blob. It only ends the
immutability restriction. The blob remains stored and may continue to
incur storage charges until deleted or moved according to supported
lifecycle settings.

A legal hold does not expire automatically. It remains until an
authorized user clears it.

------------------------------------------------------------------------

# Part 3 -- Compare Stored Access Policy and Immutable Storage

## 18. Key Differences

  -----------------------------------------------------------------------
  Area                    Stored Access Policy    Immutable Storage
  ----------------------- ----------------------- -----------------------
  Main purpose            Control access granted  Prevent data
                          by a service SAS        modification/deletion

  Protects                Access permissions and  Blob data against
                          validity for SAS tokens changes/removal
                          referencing the policy  

  Typical use             Temporary controlled    Compliance, audit,
                          access to a             legal retention
                          container/blob          

  Scope                   Container policy for    Container or blob
                          service SAS             version, depending on
                                                  configuration

  Can users read data?    According to SAS        Usually read access
                          permissions             remains available

  Can data be changed?    Depends on SAS          Blocked while covered
                          permissions and other   by active immutability
                          authorization           protection

  Revocation/control      Change or delete stored Retention policy /
                          policy                  legal hold controls

  Is it backup?           No                      No
  -----------------------------------------------------------------------

**Simple teaching explanation:** - Stored Access Policy answers: "Who
can access this data, and for how long through this service SAS?" -
Immutable Storage answers: "Can this data be changed or deleted during
the retention period?"

------------------------------------------------------------------------

# Part 4 -- Classroom Demo Sequence

## 19. Suggested 35--45 Minute Teaching Flow

  -----------------------------------------------------------------------
  Time                                Activity
  ----------------------------------- -----------------------------------
  0--5 min                            Explain SAS, stored access policy,
                                      and WORM

  5--12 min                           Create storage account, container,
                                      and sample blob

  12--20 min                          Create stored access policy,
                                      generate service SAS, test
                                      read-only access

  20--25 min                          Change/delete the stored policy and
                                      retest the SAS

  25--33 min                          Create immutable container and
                                      upload audit record

  33--40 min                          Configure time-based retention and
                                      test overwrite/delete

  40--45 min                          Compare both features and discuss
                                      production controls
  -----------------------------------------------------------------------

For a smooth class, create the Storage Account before the session
begins. Some immutability settings and SAS portal flows may differ by
account configuration and portal release.

------------------------------------------------------------------------

# Part 5 -- Troubleshooting

## 20. Stored Access Policy Troubleshooting

  -----------------------------------------------------------------------
  Problem                             Check
  ----------------------------------- -----------------------------------
  SAS returns 403                     Check SAS expiry, start time,
                                      permissions, resource URI, signed
                                      identifier, and clock skew

  Policy not available during SAS     Confirm the policy was saved on the
  generation                          correct container and generate a
                                      service SAS

  Policy change has no effect         Confirm the SAS includes the policy
                                      identifier; allow propagation;
                                      verify that it is not an account
                                      SAS or user delegation SAS

  Read works but listing fails        Confirm the SAS has List permission
                                      and is scoped to the container

  Upload unexpectedly succeeds        Verify that the token really
                                      references the stored policy and
                                      that no other credential is being
                                      used
  -----------------------------------------------------------------------

## 21. Immutable Storage Troubleshooting

  -----------------------------------------------------------------------
  Problem                             Check
  ----------------------------------- -----------------------------------
  Cannot overwrite or delete blob     Check active time-based retention
                                      or legal hold

  Cannot shorten or remove policy     It may be locked; locked policies
                                      have strict restrictions

  Portal does not show immutability   Check account type, region,
  option                              container configuration,
                                      permissions, and current feature
                                      support

  Blob remains after retention        Expiry removes the immutability
  expires                             restriction; it does not
                                      automatically delete the blob

  Cannot clean up the lab             Check for active retention, locked
                                      policy, legal hold, soft delete, or
                                      other protections before deleting
                                      resources
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Part 6 -- Security and Production Recommendations

1.  Use Microsoft Entra ID and Azure RBAC wherever possible rather than
    distributing account keys.
2.  Generate SAS tokens with the least permissions and shortest validity
    period required.
3.  Use HTTPS-only access and secure network restrictions.
4.  Treat SAS URLs as secrets. Never put them in Git repositories,
    public documentation, or screenshots.
5.  Use stored access policies when service SAS lifecycle needs
    centralized control.
6.  Remember that a stored access policy does not control account SAS or
    user delegation SAS.
7.  Use immutable storage only after compliance and retention
    requirements have been approved.
8.  Test retention and legal-hold procedures in a dedicated
    non-production account.
9.  Be especially careful before locking an immutability policy. Locked
    policies are intentionally difficult to reverse.
10. Combine immutability with monitoring, backup, access control, and
    documented retention governance.
11. Understand that immutability does not protect against every
    availability or account-level failure; it is not a complete backup
    or disaster recovery strategy.
12. Review current Azure feature support and limitations before using
    the design for regulated workloads.

------------------------------------------------------------------------

# Part 7 -- Student Assignments

## Assignment A -- Stored Access Policy

1.  Create a container named `student-sas-lab`.
2.  Upload a text file.
3.  Create a stored access policy named `StudentReadPolicy`.
4.  Grant only Read and List permissions.
5.  Generate a service SAS that references the policy.
6.  Verify that read access works.
7.  Attempt a write or delete operation and capture the denial.
8.  Change or remove the stored policy and retest the SAS.
9.  Explain why a SAS without a signed identifier is not controlled by
    that stored policy.

## Assignment B -- Immutable Storage

1.  Create a container named `student-immutable-lab`.
2.  Upload `important-record.txt`.
3.  Configure a short unlocked time-based retention policy for the lab.
4.  Attempt to overwrite and delete the blob.
5.  Record the error or blocked operation.
6.  Explain the difference between unlocked and locked policy.
7.  Explain why expiry does not automatically delete the blob.
8.  Describe when a legal hold would be appropriate.

------------------------------------------------------------------------

# Part 8 -- Interview Questions

1.  What is a Shared Access Signature (SAS)?
2.  What is the difference between service SAS, account SAS, and user
    delegation SAS?
3.  What is a stored access policy?
4.  Why would you use a stored access policy instead of an ad hoc
    service SAS?
5.  What is the signed identifier in a SAS token?
6.  Can a stored access policy control an account SAS?
7.  What happens to a service SAS when its stored access policy is
    deleted?
8.  What is immutable blob storage?
9.  What does WORM mean?
10. What is the difference between time-based retention and legal hold?
11. What is the difference between an unlocked and locked immutability
    policy?
12. Does expiry of an immutable retention period delete the blob
    automatically?
13. Is immutable storage a backup solution?
14. Can a protected blob be overwritten or deleted during its retention
    period?
15. What is the difference between stored access policy and immutable
    storage?

------------------------------------------------------------------------

# Part 9 -- Cleanup

**Before cleanup:** Ensure the lab data is disposable and that no
retention policy or legal hold remains active.

1.  Remove the legal hold from the test container, if one was created.
2.  For an unlocked time-based policy, remove or adjust it only where
    Azure permits and only after confirming that no required retention
    obligation exists.
3.  If a policy was locked, do not expect to remove it early. Wait for
    the retention period to expire and follow the supported deletion
    process.
4.  Delete test blobs and containers after protections have ended.
5.  Delete the Storage Account if it was created only for this lab.
6.  Delete the resource group `rg-sas-immutable-demo` after verifying
    that it contains no resources you need.

**Caution:** A locked immutability policy can prevent deletion of
protected data and the containing resources until retention requirements
are satisfied. For this reason, the lab instructs students to keep the
policy unlocked.

------------------------------------------------------------------------

# Official Microsoft Documentation

-   [Create a stored access
    policy](https://learn.microsoft.com/azure/storage/blobs/storage-blob-stored-access-policy)
-   [Create a service
    SAS](https://learn.microsoft.com/azure/storage/blobs/sas-service-create)
-   [Grant limited access to Azure Storage resources using
    SAS](https://learn.microsoft.com/azure/storage/common/storage-sas-overview)
-   [Immutable storage for Azure Blob
    Storage](https://learn.microsoft.com/azure/storage/blobs/immutable-storage-overview)
-   [Configure time-based retention
    policies](https://learn.microsoft.com/azure/storage/blobs/immutable-policy-configure-version-scope)
-   [Configure legal
    holds](https://learn.microsoft.com/azure/storage/blobs/immutable-legal-hold-overview)

------------------------------------------------------------------------

## Final Recap

-   **Stored Access Policy:** Centralized control for service SAS tokens
    that reference the policy identifier.
-   **Time-Based Retention:** Protects blob data from modification or
    deletion for a defined retention period.
-   **Legal Hold:** Keeps protected data immutable until an authorized
    user clears the hold.
-   **Unlocked vs Locked:** Unlocked policies are adjustable within
    Azure's rules; locked policies provide stronger compliance
    protection and are intentionally difficult to reverse.

**One-line classroom takeaway:** Stored Access Policy controls access to
blobs; Immutable Storage protects blob data from being changed or
deleted.
