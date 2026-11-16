# Azure Files --- Linux VM Mount, Share Snapshot, and Recovery

## Hands-on Lab Using Azure Portal + Linux Commands

**Goal:** Create an Azure file share in the Azure Portal, mount it on an
Ubuntu Linux VM, create files from Linux, take an Azure Files share
snapshot, delete or modify files, and recover the earlier data.

**Example architecture**

``` text
                 Azure Subscription
                         |
              Resource Group: rg-files-lab
                  /                 \
                 /                   \
       Storage Account              Ubuntu Linux VM
          (Azure Files)                 |
               |                        |
        File share: labshare <---- SMB 3.0 mount
               |
        Share snapshot
               |
        Recover previous file
```

## 1. What you will learn

By completing this lab, you will:

-   Create an Azure Storage Account and Azure Files share using the
    Azure Portal.
-   Create an Ubuntu Linux VM using the Azure Portal.
-   Configure network access for SMB.
-   Mount Azure Files on Linux.
-   Create, edit, and delete files from the Linux VM.
-   Create a share snapshot from the Azure Portal.
-   Browse a snapshot and recover an earlier file.
-   Understand the difference between a file share snapshot and a full
    backup.

## 2. Understand Azure Files and snapshots

**Azure Files** provides managed file shares in Azure. A Linux VM can
mount an Azure file share using SMB 3.x. Once mounted, the share appears
as a directory in Linux, and applications can work with it like a
network file system.

A **share snapshot** is a point-in-time, read-only copy of the file
share. It lets you recover files or folders to an earlier state.

Example:

1.  At 10:00 AM, `app.conf` contains `ENV=DEV`.
2.  You create a share snapshot.
3.  At 10:30 AM, you change the file to `ENV=PROD`.
4.  You can browse the snapshot and recover the earlier `ENV=DEV`
    content.

A share snapshot is for recovery of previous file-share state. It is not
a separate independently managed file share, and it is not a replacement
for a full backup/retention strategy.

## 3. Prerequisites and important network note

-   Azure subscription with permission to create resources.
-   An Ubuntu Linux VM (this lab uses Ubuntu 22.04/24.04).
-   Azure Storage Account with Azure Files enabled.
-   SMB 3.x support on the Linux VM.
-   Network connectivity from the VM to the Storage Account file
    endpoint.

**SMB uses TCP port 445.** Some internet service providers, corporate
networks, and cloud network policies block outbound TCP 445. For a
production deployment, prefer private connectivity such as a Storage
private endpoint over exposing SMB publicly. For this lab, use a VM and
Storage Account configuration that can reach the Azure Files endpoint on
TCP 445.

Do not open inbound TCP 445 to the public internet. The VM needs
outbound connectivity to the Storage Account file endpoint.

## 4. Create a Resource Group in Azure Portal

1.  Open <https://portal.azure.com>.

2.  Search for **Resource groups**.

3.  Select **Create**.

4.  Choose your subscription.

5.  Enter resource group name:

    `rg-files-lab`

6.  Choose a region, for example **Central India**.

7.  Select **Review + create**.

8.  Select **Create**.

## 5. Create the Storage Account

1.  Search for **Storage accounts**.
2.  Select **Create**.
3.  Select the subscription and resource group `rg-files-lab`.
4.  Enter a globally unique name, for example
    `stfileslab<unique-number>`.
5.  Select a region, for example **Central India**.
6.  Select **Standard** performance.
7.  Select **Locally-redundant storage (LRS)** for this lab.
8.  Choose **StorageV2 (general purpose v2)**.
9.  Keep **Hierarchical namespace** disabled.
10. On the **Networking** tab, choose the connectivity setting
    appropriate for your lab. If using public endpoint access, restrict
    network access as much as possible and do not expose SMB inbound to
    the VM.
11. On **Data protection**, leave the default settings for now or
    configure soft delete if available and appropriate.
12. Select **Review + create**, then **Create**.
13. Open the Storage Account after deployment.

> For production, choose redundancy, networking, identity-based
> authentication, and data protection according to your requirements.
> LRS is used here only to keep the lab simple.

## 6. Create the Azure file share

1.  In the Storage Account, open **Data storage → File shares**.

2.  Select **+ File share**.

3.  Enter the name:

    `labshare`

4.  Choose a suitable access tier, such as **Transaction optimized**,
    for this hands-on lab if the portal offers it.

5.  Set quota, for example **10 GiB**.

6.  Select **Create**.

7.  Open the new `labshare` share.

You now have an Azure file share. It is empty.

## 7. Create an Ubuntu Linux VM using the Portal

1.  Search for **Virtual machines**.

2.  Select **Create → Azure virtual machine**.

3.  Choose subscription and resource group `rg-files-lab`.

4.  Enter VM name:

    `vm-ubuntu-files`

5.  Select the same region as the Storage Account for a simple lab.

6.  Choose an Ubuntu Server LTS image, such as Ubuntu Server 24.04 LTS.

7.  Select a small VM size suitable for your lab.

8.  Configure administrator account using SSH public key authentication.

9.  On the **Networking** tab, select or create a Virtual Network and
    subnet.

10. Allow SSH (TCP 22) only from your trusted public IP address, not
    from the entire internet.

11. Do not create an inbound rule for SMB/TCP 445.

12. Select **Review + create**, then **Create**.

13. Wait for deployment to complete.

14. Open the VM and select **Connect → SSH** to view the connection
    command.

Connect from your local terminal using the SSH command shown by the
Portal.

## 8. Configure Storage Account networking

The VM must be able to reach the Storage Account's Azure Files endpoint.

### Simple lab option: public endpoint

If the Storage Account permits public endpoint access:

1.  Open the Storage Account.
2.  Go to **Security + networking → Networking**.
3.  Review **Public network access** and the firewall settings.
4.  If you use selected networks, add the VM's outbound public IP or
    configure the appropriate network access path.
5.  Save the changes.

The Storage Account firewall behavior depends on the VM's actual
outbound path. A VM's private IP is not automatically the public source
IP seen by a public Storage endpoint.

### Production option: private endpoint

For production, configure a private endpoint for the **file**
subresource, ensure private DNS resolves the Storage Account file FQDN
to the private endpoint IP, and ensure routing and NSGs allow TCP 445
from the VM to that private IP.

Do not assume a private endpoint for the `blob` subresource provides
Azure Files connectivity; Azure Files requires the `file` subresource.

## 9. Get the Azure Files connection details

In the Azure Portal:

1.  Open the Storage Account.
2.  Go to **Data storage → File shares**.
3.  Open `labshare`.
4.  Select **Connect** (or the portal's equivalent connection option).
5.  Select **Linux**.
6.  Review the generated mount instructions.

The portal may show a mount command and connection details for the
selected Linux distribution.

For this lab, we will use the Storage Account name and one of its access
keys. Treat the key like a password.

To find the account key:

1.  Open the Storage Account.
2.  Go to **Security + networking → Access keys**.
3.  Select **Show** for key1.
4.  Copy the key securely.
5.  Do not paste the key into notes, source control, screenshots, or
    shared terminals.

**Security note:** Storage Account keys grant broad access. For
production, prefer identity-based authentication for Azure Files where
supported by your configuration, or use a carefully governed
secret-management solution. Use the key-based example below only for a
controlled lab.

## 10. Mount Azure Files on Ubuntu

SSH into `vm-ubuntu-files`.

### Step 1 --- Install CIFS utilities

``` bash
sudo apt-get update
sudo apt-get install -y cifs-utils
```

### Step 2 --- Create a mount point

``` bash
sudo mkdir -p /mnt/azurefiles
```

### Step 3 --- Set variables

Replace the values with your actual Storage Account name and key:

``` bash
STORAGE_ACCOUNT="<your-storage-account-name>"
SHARE_NAME="labshare"
STORAGE_KEY="<your-storage-account-key>"
```

### Step 4 --- Create a protected credentials file

``` bash
sudo bash -c "cat > /etc/smbcredentials-${STORAGE_ACCOUNT}.cred <<EOF
username=${STORAGE_ACCOUNT}
password=${STORAGE_KEY}
EOF"

sudo chmod 600 "/etc/smbcredentials-${STORAGE_ACCOUNT}.cred"
```

The key is now stored in a root-readable credentials file rather than
embedded in the mount command.

### Step 5 --- Mount the share

``` bash
sudo mount -t cifs \
  "//${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE_NAME}" \
  /mnt/azurefiles \
  -o "credentials=/etc/smbcredentials-${STORAGE_ACCOUNT}.cred,serverino,nosharesock,actimeo=30,mfsymlinks,vers=3.1.1,dir_mode=0777,file_mode=0777"
```

For a real multi-user environment, do not use permissive `0777` modes
without considering your security requirements. Configure ownership,
modes, and access controls deliberately.

### Step 6 --- Verify the mount

``` bash
df -hT | grep azurefiles
mount | grep azurefiles
```

You should see the Azure file share mounted at `/mnt/azurefiles`.

If the mount fails, check DNS resolution and outbound TCP 445:

``` bash
nslookup "${STORAGE_ACCOUNT}.file.core.windows.net"
nc -vz "${STORAGE_ACCOUNT}.file.core.windows.net" 445
```

If `nc` is not installed:

``` bash
sudo apt-get install -y netcat-openbsd
```

If TCP 445 is blocked, fix the network path or use private connectivity.
Do not try to solve it by opening inbound TCP 445 to the VM.

## 11. Create test files from Linux

Create a directory and files in the mounted share:

``` bash
sudo mkdir -p /mnt/azurefiles/project
sudo tee /mnt/azurefiles/project/app.conf <<'EOF'
APP_NAME=TrainingApp
ENVIRONMENT=DEV
PORT=8080
VERSION=1.0
EOF

sudo tee /mnt/azurefiles/project/readme.txt <<'EOF'
This file is stored in Azure Files and mounted on an Ubuntu VM.
EOF
```

Verify:

``` bash
ls -lR /mnt/azurefiles
cat /mnt/azurefiles/project/app.conf
```

### Verify from Azure Portal

1.  Open the Storage Account.
2.  Go to **File shares → labshare**.
3.  Open the `project` directory.
4.  Verify that `app.conf` and `readme.txt` are visible.

This demonstrates that files created on the Linux VM are stored in Azure
Files, not only on the VM's local disk.

## 12. Create a share snapshot using Azure Portal

Now create a point-in-time snapshot.

1.  Open the Storage Account in Azure Portal.
2.  Go to **Data storage → File shares**.
3.  Select `labshare`.
4.  Locate **Snapshots** or the **Create snapshot** action in the
    file-share toolbar or menu.
5.  Select **Create snapshot**.
6.  Confirm the operation.
7.  Open the share's snapshot view and verify that a snapshot is listed.

Portal labels and the location of snapshot actions can change. If the
action is not visible in the share view, use the share's **Snapshots**
or **Manage snapshots** entry in the current portal experience.

**Teaching point:** A share snapshot captures the file share at a point
in time. It is read-only and preserves the earlier file state.

## 13. Simulate accidental change or deletion

Return to the Linux VM.

### Change the file

``` bash
sudo tee /mnt/azurefiles/project/app.conf <<'EOF'
APP_NAME=TrainingApp
ENVIRONMENT=PROD
PORT=9090
VERSION=2.0
EOF

cat /mnt/azurefiles/project/app.conf
```

### Delete another file

``` bash
sudo rm /mnt/azurefiles/project/readme.txt
ls -lR /mnt/azurefiles
```

The current share now has modified `app.conf` and no `readme.txt`.

Verify the current state in Azure Portal by refreshing the `labshare`
view.

## 14. Recover an earlier file from the snapshot

The recovery method is to browse the snapshot, locate the earlier file,
and copy its content back to the live share.

1.  In Azure Portal, open the Storage Account.
2.  Open **File shares → labshare**.
3.  Open **Snapshots** or **Manage snapshots**.
4.  Select the snapshot created in Step 12.
5.  Browse the snapshot contents.
6.  Open the `project` directory.
7.  Locate `app.conf` and `readme.txt`.
8.  Download the earlier `app.conf` from the snapshot.
9.  Upload or copy it back into the live `labshare/project` directory,
    replacing the modified file.
10. Upload or copy the earlier `readme.txt` back into the live
    directory.

The exact portal controls for browsing, downloading, and restoring may
vary. The key recovery workflow is: select the snapshot, retrieve the
earlier file, and restore it into the current share. Do not assume that
selecting a snapshot automatically rolls back the entire live share.

### Verify recovery from Linux

On the VM:

``` bash
cat /mnt/azurefiles/project/app.conf
cat /mnt/azurefiles/project/readme.txt
```

Expected earlier content:

``` text
APP_NAME=TrainingApp
ENVIRONMENT=DEV
PORT=8080
VERSION=1.0
```

The deleted `readme.txt` should also be present again.

**Important:** Restoring a file means copying the snapshot's file
content back into the live share. The snapshot remains a read-only
point-in-time copy.

## 15. Alternative recovery using Linux copy commands

If you have downloaded the snapshot files to the VM or another
accessible location, copy them back into the mounted share.

For example, if the recovered files are available under
`/tmp/recovery/project/`:

``` bash
sudo mkdir -p /mnt/azurefiles/project
sudo cp /tmp/recovery/project/app.conf /mnt/azurefiles/project/app.conf
sudo cp /tmp/recovery/project/readme.txt /mnt/azurefiles/project/readme.txt
```

Verify:

``` bash
cat /mnt/azurefiles/project/app.conf
ls -l /mnt/azurefiles/project
```

This is a file-level recovery example. It does not automatically restore
permissions, ownership, ACLs, or every other file-system property.
Validate the required metadata for production recovery.

## 16. Mount automatically after reboot (optional)

For a lab, you can configure `/etc/fstab`, but be careful: an invalid
entry can delay boot or cause mount failures.

A safer approach is to use a credentials file and the `nofail` and
systemd automount options.

Edit:

``` bash
sudo nano /etc/fstab
```

Add one line, replacing the account name:

``` text
//<storage-account>.file.core.windows.net/labshare /mnt/azurefiles cifs credentials=/etc/smbcredentials-<storage-account>.cred,vers=3.1.1,serverino,nosharesock,actimeo=30,mfsymlinks,dir_mode=0770,file_mode=0660,nofail,_netdev,x-systemd.automount 0 0
```

Test the configuration:

``` bash
sudo systemctl daemon-reload
sudo mount -a
df -hT | grep azurefiles
```

Do not reboot until `mount -a` completes successfully. For production,
validate boot behavior and use a managed secret/identity approach.

## 17. Snapshot vs soft delete vs backup

  -----------------------------------------------------------------------
  Feature                 What it provides        Typical use
  ----------------------- ----------------------- -----------------------
  Azure Files share       Point-in-time,          Recover earlier
  snapshot                read-only view of the   file/folder content
                          share                   

  Azure Files soft delete Recovery window for     Recover an accidentally
                          deleted shares, when    deleted share
                          enabled and supported   

  Azure Backup for Azure  Managed backup and      Operational backup and
  Files                   recovery capabilities   longer-term protection
                          with policies and       
                          retention               
  -----------------------------------------------------------------------

A share snapshot is useful for quick point-in-time recovery, but it is
not the same as a full backup strategy. Configure Azure Backup and soft
delete according to your recovery requirements.

## 18. Troubleshooting

  --------------------------------------------------------------------------
  Problem                                Checks and possible fix
  -------------------------------------- -----------------------------------
  `mount error(13): Permission denied`   Check Storage Account name/key,
                                         share name, credentials file, and
                                         whether the key was copied
                                         correctly

  `mount error(115)` or connection       Check DNS, outbound TCP 445,
  timeout                                routing, firewall, and Storage
                                         Account network rules

  `No such file or directory`            Confirm the share name and mount
                                         path

  `Host is down`                         Check name resolution and TCP 445
                                         connectivity

  Files are not visible in Portal        Confirm the VM is writing to the
                                         mounted path and the mount is
                                         active

  Snapshot option is not visible         Check the current portal's File
                                         shares snapshot/management view and
                                         account support

  File recovery is incomplete            Confirm you selected the intended
                                         snapshot and restored the correct
                                         directory/file; validate metadata
                                         separately

  Mount works until reboot               Check `/etc/fstab`, credentials
                                         file permissions, network
                                         readiness, and systemd automount
                                         settings
  --------------------------------------------------------------------------

Useful Linux checks:

``` bash
findmnt /mnt/azurefiles
df -hT
mount | grep cifs
dmesg | tail -50
```

## 19. Security and production recommendations

-   Prefer private endpoints for Azure Files in production.
-   Use private DNS for the `file` subresource when using a private
    endpoint.
-   Never expose inbound SMB/TCP 445 on a VM.
-   Avoid storing Storage Account keys in scripts or source control.
-   Prefer identity-based authentication where supported by the
    deployment and client configuration.
-   Restrict Storage Account network access and data-plane permissions.
-   Use appropriate file and directory permissions; avoid blanket `0777`
    in production.
-   Configure soft delete and Azure Backup based on recovery objectives.
-   Monitor storage usage, snapshot retention, and backup job status.
-   Test recovery regularly rather than assuming a snapshot or backup is
    usable.

## 20. Student assignment

1.  Create a second directory named `website`.
2.  Create `index.html` and `settings.conf` from the Linux VM.
3.  Verify both files in the Azure Portal.
4.  Create a share snapshot.
5.  Change `index.html` and delete `settings.conf`.
6.  Recover both files from the snapshot.
7.  Verify the recovered content from Linux.
8.  Explain why a snapshot is read-only.
9.  Explain why a share snapshot is not a complete backup strategy.
10. Research how Azure Backup for Azure Files can be configured for
    scheduled recovery points.

## 21. Interview questions

1.  What is Azure Files?
2.  How can a Linux VM mount an Azure file share?
3.  Which protocol is commonly used for mounting Azure Files on Linux?
4.  Which TCP port does SMB use?
5.  What is an Azure Files share snapshot?
6.  Is a share snapshot writable?
7.  How can you recover a deleted file using a share snapshot?
8.  What is the difference between a share snapshot and Azure Backup?
9.  Why should Storage Account keys be protected?
10. Why are private endpoints recommended for production Azure Files
    deployments?
11. What is the purpose of `/etc/fstab`?
12. How would you troubleshoot an SMB mount timeout?

## 22. Cleanup

1.  Unmount the share from Linux:

    ``` bash
    sudo umount /mnt/azurefiles
    ```

2.  Remove the `/etc/fstab` entry if you added one.

3.  Remove the lab credentials file:

    ``` bash
    sudo rm -f "/etc/smbcredentials-${STORAGE_ACCOUNT}.cred"
    ```

4.  In Azure Portal, confirm that the Resource Group contains only lab
    resources.

5.  Delete `rg-files-lab` only if it is dedicated to this exercise.

Deleting the Resource Group permanently deletes the VM, Storage Account,
file share, snapshots, and other resources within it. Never do this to a
shared or production Resource Group.

------------------------------------------------------------------------

## Official Microsoft documentation

-   [Azure Files
    overview](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction)
-   [Mount Azure Files on
    Linux](https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-linux)
-   [Create and manage Azure file share
    snapshots](https://learn.microsoft.com/en-us/azure/storage/files/storage-snapshots-files)
-   [Azure Files networking
    considerations](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-networking-overview)
-   [Azure Files identity-based
    authentication](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-active-directory-overview)
-   [Azure Backup for Azure
    Files](https://learn.microsoft.com/en-us/azure/backup/azure-file-share-backup-overview)

**Trainer's closing explanation:** Azure Files gives a Linux VM a
managed shared file system over SMB. A share snapshot preserves the
share's earlier state. If a file is accidentally changed or deleted,
browse the snapshot, retrieve the earlier file, and copy it back into
the live share. For production, combine appropriate network security,
identity, soft delete, and Azure Backup.
