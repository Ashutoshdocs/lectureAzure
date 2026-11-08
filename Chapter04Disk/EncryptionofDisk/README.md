# Azure VM Encryption – CLI Commands Explained

A quick reference for checking and enabling encryption on Azure VMs and managed disks with the Azure CLI.

> **Key idea:** Azure has two separate encryption layers.
> - **Server-Side Encryption (SSE)** encrypts managed disks at rest in Azure Storage. It is **always on**.
> - **Encryption at Host (EAH)** is **optional**. It also encrypts the VM host's temp disk and OS/data disk caches, and data flows to Storage already encrypted. This gives end-to-end encryption.

---

## Contents

1. [Prerequisites](#prerequisites)
2. [Variables](#variables)
3. [Command reference](#command-reference)
4. [Enable Encryption at Host](#enable-encryption-at-host)
5. [Quick audit script](#quick-audit-script)
6. [Summary](#summary)
7. [References](#references)

---

## Prerequisites

- Azure CLI installed and signed in (`az login`)
- **Contributor** (or higher) on the subscription to register features and update VMs
- A VM size that supports Encryption at Host in your region

## Variables

Set these once so every command below can be copied as-is:

```bash
SUBSCRIPTION_ID="<your-subscription-id>"
RG="firewall"
VM="myVm"
OS_DISK=$(az vm show -g $RG -n $VM --query storageProfile.osDisk.name -o tsv)
```

> Looking up the OS disk name avoids hard-coding long names such as `myVm_OsDisk_1_12b00626...`.

---

## Command reference

| # | Command | What it does | Changes resources? |
|---|---------|--------------|--------------------|
| 1 | `az account set` | Picks the subscription to work in | No |
| 2 | `az feature register` | Registers Encryption at Host for the subscription | Yes (subscription) |
| 3 | `az feature show` | Checks the registration state | No |
| 4 | `az disk show ... encryption.type` | Shows which key encrypts the disk at rest | No |
| 5 | `az vm show ... encryptionAtHost` | Shows whether EAH is on for the VM | No |
| 6 | `az disk show ... encryption` | Shows the full disk encryption settings | No |

### 1. Set the active subscription

```bash
az account set --subscription "$SUBSCRIPTION_ID"
```

- Sets which subscription the following commands run in. This matters when you can access several subscriptions.
- Changes only your local CLI settings, not any Azure resource.
- Confirm with `az account show --query name -o tsv`.

### 2. Register the Encryption at Host feature

```bash
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

- Encryption at Host must be registered once per subscription before any VM can use it.
- Registration takes a few minutes.
- After it shows **Registered**, refresh the provider so the change takes effect:

```bash
az provider register --namespace Microsoft.Compute
```

### 3. Check registration status

```bash
az feature show --namespace Microsoft.Compute --name EncryptionAtHost \
  --query properties.state -o tsv
```

| State | Meaning |
|-------|---------|
| `Registering` | Still in progress. Wait and re-check. |
| `Registered` | Ready to use. |
| `NotRegistered` | Not registered yet. Run step 2. |

### 4. Check disk encryption type (at rest)

```bash
az disk show -g $RG -n $OS_DISK --query encryption.type -o tsv
```

Managed disks are **always** encrypted at rest with SSE. This shows **which key** is used:

| Output | Meaning |
|--------|---------|
| `EncryptionAtRestWithPlatformKey` | Microsoft-managed key (default) |
| `EncryptionAtRestWithCustomerKey` | Customer-managed key (CMK) through a Disk Encryption Set |
| `EncryptionAtRestWithPlatformAndCustomerKeys` | Double encryption: one platform key and one customer key |

### 5. Check Encryption at Host on the VM

```bash
az vm show -g $RG -n $VM --query securityProfile.encryptionAtHost -o tsv
```

| Output | Meaning |
|--------|---------|
| `true` | Encryption at Host is enabled |
| `false` or empty | Not enabled |

### 6. Show the full disk encryption settings

```bash
az disk show -g $RG -n $OS_DISK --query encryption -o json
```

Example output:

```json
{
  "diskEncryptionSetId": null,
  "type": "EncryptionAtRestWithPlatformKey"
}
```

- `diskEncryptionSetId` holds the Disk Encryption Set's resource ID when a customer-managed key is used.
- Use this for security audits, compliance evidence and troubleshooting.

---

## Enable Encryption at Host

### On a new VM

```bash
az vm create -g $RG -n $VM --image Ubuntu2204 --size Standard_D2s_v5 \
  --encryption-at-host --generate-ssh-keys
```

### On an existing VM (requires downtime)

The VM **must be deallocated** first:

```bash
az vm deallocate -g $RG -n $VM
az vm update     -g $RG -n $VM --set securityProfile.encryptionAtHost=true
az vm start      -g $RG -n $VM
```

> ⚠️ Deallocating stops the VM and releases a dynamic public IP. Plan a maintenance window.

To disable it, deallocate the VM and run the same update with `encryptionAtHost=false`.

---

## Quick audit script

```bash
echo "Subscription : $(az account show --query name -o tsv)"
echo "EAH feature  : $(az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv)"
echo "VM EAH       : $(az vm show -g $RG -n $VM --query securityProfile.encryptionAtHost -o tsv)"

for d in $(az vm show -g $RG -n $VM --query "[storageProfile.osDisk.name, storageProfile.dataDisks[].name][]" -o tsv); do
  echo "Disk $d : $(az disk show -g $RG -n $d --query encryption.type -o tsv)"
done
```

---

## Summary

| Topic | Fact |
|-------|------|
| Disk encryption at rest (SSE) | Always on for managed disks; uses a platform key by default |
| Encryption at Host | Optional, extra layer: also covers temp disk and caches |
| Relationship | Separate features; they can be used together |
| Feature registration | Required once per subscription |
| Existing VMs | **Can** enable EAH, but only after deallocating the VM |
| Key choice | Platform key, customer key (Disk Encryption Set), or both |

---

## References

- [Enable encryption at host – Azure CLI](https://learn.microsoft.com/azure/virtual-machines/linux/disks-enable-host-based-encryption-cli)
- [Enable encryption at host – Azure portal](https://learn.microsoft.com/azure/virtual-machines/disks-enable-host-based-encryption-portal)
- [EncryptionType values (Azure SDK)](https://learn.microsoft.com/javascript/api/@azure/arm-compute/encryptiontype)
