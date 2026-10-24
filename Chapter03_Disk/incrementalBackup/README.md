# Lab: Prove Azure Incremental Snapshots Store Only Changed Data

This hands-on lab creates a VM, writes a file, takes **Snapshot 1**, writes more data, takes **Snapshot 2**, and then **proves** that Snapshot 2 contains only the new data — not a full copy of the disk. It finishes by turning the measured numbers into storage and cost savings.

```
 ┌──────────────┐   write 1 GiB    ┌──────────────┐   write 2 GiB    ┌──────────────┐
 │  Empty disk  │ ───────────────► │  Snapshot 1  │ ───────────────► │  Snapshot 2  │
 │   (32 GiB)   │   file1.bin      │  ≈ 1 GiB     │   file2.bin      │  ≈ 2 GiB     │
 └──────────────┘                  └──────────────┘                  └──────────────┘
                                     baseline                          ONLY the delta
```

**Time:** ~20 minutes  **Cost:** a few cents if you delete everything at the end (Step 10)
**Run from:** [Azure Cloud Shell](https://shell.azure.com) (Bash) or any machine with Azure CLI and Python 3

---

## Step 0 — Set variables

```bash
RG="rg-incremental-snapshot-lab"
LOCATION="centralindia"
VM="vm-snaplab"
SNAP1="snap1-baseline"
SNAP2="snap2-incremental"
```

---

## Step 1 — Create the resource group and VM with an empty data disk

```bash
az group create -n $RG -l $LOCATION

az vm create \
  -g $RG -n $VM \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --data-disk-sizes-gb 32 \
  --public-ip-address ""          # no public IP needed; we use run-command

# Capture the data disk's resource ID
DISK_ID=$(az vm show -g $RG -n $VM \
  --query "storageProfile.dataDisks[0].managedDisk.id" -o tsv)
echo $DISK_ID
```

---

## Step 2 — Format and mount the data disk

`lazy_itable_init=0` makes the filesystem finish all its initialization writes now, so they don't leak into Snapshot 2's delta later.

```bash
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  DEV=/dev/disk/azure/scsi1/lun0
  mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0 $DEV
  mkdir -p /data
  mount $DEV /data
  df -h /data
' --query "value[0].message" -o tsv
```

---

## Step 3 — Create the first file (1 GiB of random data)

Random data is used so nothing can be compressed or deduplicated away — every byte is real.

```bash
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  dd if=/dev/urandom of=/data/file1.bin bs=1M count=1024 status=none
  sync
  ls -lh /data
  sha256sum /data/file1.bin
' --query "value[0].message" -o tsv
```

📝 **Note the SHA-256 of `file1.bin`** — you'll use it in Step 9.

---

## Step 4 — Take Snapshot 1 (incremental baseline)

```bash
az snapshot create \
  -g $RG -n $SNAP1 \
  --source $DISK_ID \
  --incremental true \
  -l $LOCATION \
  --query "{name:name, incremental:incremental, state:provisioningState}" -o table
```

The **first** incremental snapshot of a disk is the baseline: it stores all used blocks on the disk (≈ 1 GiB of file data plus filesystem metadata).

---

## Step 5 — Add more data (2 GiB more)

```bash
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  dd if=/dev/urandom of=/data/file2.bin bs=1M count=2048 status=none
  sync
  ls -lh /data
  sha256sum /data/file1.bin /data/file2.bin
' --query "value[0].message" -o tsv
```

📝 **Note both SHA-256 values.** The disk now holds ≈ 3 GiB of data.

---

## Step 6 — Take Snapshot 2 (incremental)

```bash
az snapshot create \
  -g $RG -n $SNAP2 \
  --source $DISK_ID \
  --incremental true \
  -l $LOCATION \
  --query "{name:name, incremental:incremental, state:provisioningState}" -o table
```

---

## Step 7 — Look at both snapshots in Azure

```bash
az snapshot list -g $RG \
  --query "[].{name:name, incremental:incremental, diskSizeGb:diskSizeGb, created:timeCreated}" \
  -o table
```

Example output:

```
Name               Incremental    DiskSizeGb    Created
-----------------  -------------  ------------  --------------------------------
snap1-baseline     True           32            2026-10-24T09:05:11.123456+00:00
snap2-incremental  True           32            2026-10-24T09:12:47.654321+00:00
```

> ⚠️ `diskSizeGb` shows **32 for both** — that's the size of the disk the snapshot can restore, **not** what it stores or what you're billed for. To see what's actually stored, we need to look at the snapshot's data blocks (Step 8).

---

## Step 8 — PROVE Snapshot 2 holds only the incremental data

Azure lets you read a snapshot's **page ranges** (the blocks that contain data) through a temporary read-only SAS URL. It also lets you ask for **only the ranges that changed between two snapshots**. We'll measure three things:

| Measurement | What it answers |
|---|---|
| **A.** Data in Snapshot 1 | How big is the baseline? |
| **B.** Data visible through Snapshot 2 | What would a *full* backup of the disk now contain? |
| **C.** Changed data between Snapshot 1 → Snapshot 2 | What Snapshot 2 *actually* stores and bills |

### 8.1 Create the measurement script

```bash
cat > page_ranges.py <<'EOF'
#!/usr/bin/env python3
"""
Sum the data stored in an Azure managed-disk snapshot, using the Get Page Ranges API.

  page_ranges.py <SNAPSHOT_SAS>                 -> all data blocks in the snapshot
  page_ranges.py <SNAPSHOT_SAS> <PREVIOUS_SAS>  -> only blocks changed since PREVIOUS
"""
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

API_VERSION = "2021-08-06"


def data_bytes(sas_url, previous_sas_url=None):
    total, marker = 0, None
    while True:
        url = sas_url + "&comp=pagelist"
        if marker:
            url += "&marker=" + urllib.parse.quote(marker)
        req = urllib.request.Request(url, headers={"x-ms-version": API_VERSION})
        if previous_sas_url:
            # Diff mode: return only ranges that changed since the previous snapshot
            req.add_header("x-ms-previous-snapshot-url", previous_sas_url)
        with urllib.request.urlopen(req) as resp:
            root = ET.fromstring(resp.read())
        # <PageRange> = blocks holding data (or changed data, in diff mode).
        # <ClearRange> = blocks cleared since the previous snapshot; they store nothing.
        for r in root.findall("PageRange"):
            total += int(r.findtext("End")) - int(r.findtext("Start")) + 1
        marker = root.findtext("NextMarker")
        if not marker:
            return total


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    n = data_bytes(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
    print(f"{n:,} bytes  ({n / 1024**3:.2f} GiB)")
EOF
chmod +x page_ranges.py
```

### 8.2 Grant temporary read access to both snapshots

```bash
SAS1=$(az snapshot grant-access -g $RG -n $SNAP1 \
  --duration-in-seconds 3600 --query accessSas -o tsv)
SAS2=$(az snapshot grant-access -g $RG -n $SNAP2 \
  --duration-in-seconds 3600 --query accessSas -o tsv)
```

### 8.3 Measure

```bash
echo "A. Data in Snapshot 1 (baseline):"
./page_ranges.py "$SAS1"

echo "B. Data visible through Snapshot 2 (what a FULL backup would copy):"
./page_ranges.py "$SAS2"

echo "C. Data changed between Snapshot 1 and Snapshot 2 (what Snapshot 2 really stores):"
./page_ranges.py "$SAS2" "$SAS1"
```

Example output (your exact bytes will differ slightly because of filesystem metadata and the journal):

```
A. Data in Snapshot 1 (baseline):
1,190,526,976 bytes  (1.11 GiB)
B. Data visible through Snapshot 2 (what a FULL backup would copy):
3,345,883,136 bytes  (3.12 GiB)
C. Data changed between Snapshot 1 and Snapshot 2 (what Snapshot 2 really stores):
2,155,356,160 bytes  (2.01 GiB)
```

### 8.4 Read the proof

```
 B (full view of disk)          ████████████████████████████████  3.12 GiB
 C (Snapshot 2 really stores)   █████████████████████             2.01 GiB
 A (Snapshot 1 baseline)        ███████████                       1.11 GiB

                       A  +  C  =  B
                    1.11 + 2.01 = 3.12 GiB  ✔
```

- **C ≈ 2 GiB** — exactly the size of `file2.bin` (plus a little filesystem metadata). Snapshot 2 did **not** copy `file1.bin` again.
- **C ≠ B** — if Snapshot 2 were a full backup it would hold 3.12 GiB. It holds 2.01 GiB.
- **A + C = B** — Snapshot 2 reuses Snapshot 1's blocks and adds only the delta.

### 8.5 Revoke access

```bash
az snapshot revoke-access -g $RG -n $SNAP1
az snapshot revoke-access -g $RG -n $SNAP2
```

---

## Step 9 — Prove Snapshot 2 is still a complete restore point

Incremental doesn't mean partial. Restore a disk from **Snapshot 2 alone** and both files come back intact.

```bash
SNAP2_ID=$(az snapshot show -g $RG -n $SNAP2 --query id -o tsv)

az disk create -g $RG -n disk-restored-from-snap2 --source $SNAP2_ID --sku Standard_LRS -l $LOCATION
az vm disk attach -g $RG --vm-name $VM --name disk-restored-from-snap2 --lun 1

az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  mkdir -p /restored
  mount -o ro /dev/disk/azure/scsi1/lun1 /restored
  ls -lh /restored
  sha256sum /restored/file1.bin /restored/file2.bin
' --query "value[0].message" -o tsv
```

✅ The SHA-256 values match the ones from Step 5. A disk created from a 2 GiB incremental snapshot contains all 3 GiB of data — Azure supplies `file1.bin` from the baseline blocks behind the scenes.

---

## Step 10 — Translate the proof into storage and money

Using the measured values from Step 8 and an illustrative snapshot price of **$0.05 per GiB per month** (Standard LRS/ZRS — check your region's rate on the [Managed Disks pricing page](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)):

| | Full snapshots | Incremental snapshots |
|---|---|---|
| Snapshot 1 | 1.11 GiB | 1.11 GiB |
| Snapshot 2 | 3.12 GiB (full copy) | **2.01 GiB** (delta only) |
| **Total stored** | **4.23 GiB** | **3.12 GiB** |
| **Monthly cost** | $0.21 | $0.16 |
| **Saved** | — | **1.11 GiB · 26%** |

The lab saves "only" 26% because we changed 2 GiB on a disk holding 1 GiB — a 200% change rate, far higher than real workloads. The savings equal exactly the data that **didn't** change: everything in Snapshot 1 that Snapshot 2 didn't have to store again.

### At realistic scale

The same mechanism on a production disk with **500 GiB used** and **20 GiB changed per day**:

| Backups kept | Full snapshots | Incremental snapshots | Storage saved | Monthly saved (@ $0.05) |
|---|---|---|---|---|
| 2 | 1,000 GiB | 520 GiB | 48.0% | $24.00 |
| 7 (one week) | 3,500 GiB | 620 GiB | 82.3% | $144.00 |
| 30 (one month) | 15,000 GiB | 1,080 GiB | 92.8% | $696.00 |

```
Full storage        = N × Used
Incremental storage = Used + (N − 1) × Changed
```

At 30 daily restore points that's about **$8,350 per year saved on one disk**.

### Confirm on your bill

After 24–48 hours, open **Cost Management → Cost analysis**, filter by resource group `rg-incremental-snapshot-lab`, and group by **Resource**. `snap2-incremental` is billed for roughly 2 GiB, not the full 3 GiB.

---

## Step 11 — Clean up

```bash
az group delete -n $RG --yes --no-wait
```

This deletes the VM, disks and both snapshots.

---

## How it works

- Azure tracks which 512-byte pages of a managed disk change between snapshots.
- The **first** incremental snapshot stores every used page.
- Each **later** incremental snapshot stores only pages changed since the previous one, and points to the earlier snapshots for everything else.
- Incremental snapshots are always kept on Standard storage (even for Premium SSD disks) and billed per GiB of data actually stored.
- Deleting Snapshot 1 is safe: Azure keeps the pages Snapshot 2 still needs, so Snapshot 2 stays fully restorable.

## Troubleshooting

| Problem | Fix |
|---|---|
| `HTTP Error 403` from `page_ranges.py` | The SAS expired or was revoked; re-run Step 8.2. |
| `HTTP Error 400` in diff mode | Both snapshots must be incremental and come from the same disk. |
| Delta C is noticeably bigger than 2 GiB | The filesystem was still initializing; make sure Step 2 used `lazy_itable_init=0,lazy_journal_init=0`. |
| `mount` fails on `/dev/disk/azure/scsi1/lun1` | Wait a few seconds after `az vm disk attach` and retry. |
| `Standard_B2s` not available in your region | Pick another size, e.g. `--size Standard_D2s_v5`. |

## References

- [Create an incremental snapshot for managed disks](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-incremental-snapshots)
- [Get Page Ranges REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/get-page-ranges)
- [Azure Managed Disks pricing](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)
