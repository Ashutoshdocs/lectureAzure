# Lab (Azure Portal): Prove Incremental Snapshots Store Only Changed Data

This lab is done almost entirely in the **Azure portal**. You will:

1. Create a VM with an empty data disk
2. Write a **1 GiB** file → take **Snapshot 1**
3. Write **2 GiB** more → take **Snapshot 2**
4. **Prove** Snapshot 2 stores only the new ~2 GiB, not a full copy of the disk
5. Prove Snapshot 2 can still restore **everything**
6. Turn the measured numbers into storage and cost savings

```
 ┌──────────────┐   write 1 GiB    ┌──────────────┐   write 2 GiB    ┌──────────────┐
 │  Empty disk  │ ───────────────► │  Snapshot 1  │ ───────────────► │  Snapshot 2  │
 │   (32 GiB)   │   file1.bin      │  ≈ 1 GiB     │   file2.bin      │  ≈ 2 GiB     │
 └──────────────┘                  └──────────────┘                  └──────────────┘
                                     baseline                          ONLY the delta
```

**Time:** ~30 minutes  **Cost:** a few cents if you delete everything at the end
**You need:** an Azure subscription and a browser. Commands inside the VM run through the portal's **Run command** page; one verification script runs in **Cloud Shell**, which opens inside the portal.

> Prefer the command line? See [README-cli.md](README-cli.md).
>
> Portal menus change from time to time. If a button has moved, use the portal's top search bar to find the page by name.

**Names used in this lab**

| Item | Name |
|---|---|
| Resource group | `rg-incremental-snapshot-lab` |
| Region | Central India (any region works) |
| VM | `vm-snaplab` |
| Data disk | `vm-snaplab_DataDisk_0` (the portal's default name) |
| Snapshot 1 | `snap1-baseline` |
| Snapshot 2 | `snap2-incremental` |

---

## Step 1 — Create a resource group

1. In the portal search bar, type **Resource groups** and open it.
2. Click **+ Create**.
3. **Resource group:** `rg-incremental-snapshot-lab`. **Region:** Central India.
4. Click **Review + create**, then **Create**.

---

## Step 2 — Create the VM with an empty 32 GiB data disk

1. Search for **Virtual machines** and open it. Click **+ Create** → **Azure virtual machine**.
2. **Basics** tab:

   | Field | Value |
   |---|---|
   | Resource group | `rg-incremental-snapshot-lab` |
   | Virtual machine name | `vm-snaplab` |
   | Region | Central India |
   | Image | **Ubuntu Server 22.04 LTS** |
   | Size | **Standard_B2s** (or any small size available) |
   | Authentication type | SSH public key → *Generate new key pair* |
   | Username | `azureuser` |
   | Public inbound ports | **None** (we never SSH in; Run command is enough) |

3. Open the **Disks** tab. Under **Data disks**, click **Create and attach a new disk**:
   - **Size:** 32 GiB
   - **Disk SKU:** Standard SSD (any SKU works; snapshots are stored on Standard storage regardless)
   - Click **OK**. It should appear with **LUN 0**.
4. Click **Review + create** → **Create**. When asked, **Download private key and create resource**.
5. Wait for *Your deployment is complete*, then click **Go to resource**.

---

## Step 3 — Format and mount the data disk

1. On the VM page, in the left menu open **Operations** → **Run command** → **RunShellScript**.
2. Paste the script below and click **Run**. Wait for the output to appear (about a minute).

```bash
# Format the empty data disk (LUN 0) and mount it at /data.
# lazy_*_init=0 finishes all filesystem setup now, so it can't leak into Snapshot 2 later.
DEV=/dev/disk/azure/scsi1/lun0
mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0 $DEV
mkdir -p /data
mount $DEV /data
df -h /data
```

✅ **Expected output** ends with a line showing `/data` with about **31G** size.

---

## Step 4 — Generate data: write file 1 (1 GiB)

Open **Run command** → **RunShellScript** again, paste, and **Run**:

```bash
# Generate 1 GiB of random (incompressible) data on the data disk
mountpoint -q /data || { echo "ERROR: /data is not mounted - rerun Step 3"; exit 1; }
dd if=/dev/urandom of=/data/file1.bin bs=1M count=1024 status=none
sync
echo "---- files on /data ----"
ls -lh /data
echo "---- checksums ----"
sha256sum /data/file1.bin
```

✅ **Expected:** `file1.bin` listed at **1.0G**, plus one SHA-256 line.
📝 **Copy the checksum somewhere** — you'll compare it in Step 10.

❗ If you see `ERROR` or `No such file`, fix it before continuing. Snapshot 1 must contain `file1.bin`.

---

## Step 5 — Take Snapshot 1 (incremental)

1. Search for **Disks** and open it. Click **`vm-snaplab_DataDisk_0`** (the data disk, **not** the `_OsDisk_` one).
2. At the top of the disk page, click **+ Create snapshot**.
3. **Basics** tab:

   | Field | Value |
   |---|---|
   | Resource group | `rg-incremental-snapshot-lab` |
   | Name | `snap1-baseline` |
   | **Snapshot type** | **Incremental** ← important |
   | Storage type | Standard (default) |

4. Click **Review + create** → **Create**.

The **first** incremental snapshot of a disk is the baseline: it stores all used blocks (≈ 1 GiB of file data plus filesystem metadata).

---

## Step 6 — Generate more data: write file 2 (2 GiB)

Back on **`vm-snaplab`** → **Run command** → **RunShellScript**:

```bash
# Generate 2 GiB MORE random data; file1 stays untouched
mountpoint -q /data || { echo "ERROR: /data is not mounted - rerun Step 3"; exit 1; }
test -f /data/file1.bin || { echo "ERROR: file1.bin missing - see Troubleshooting"; exit 1; }
dd if=/dev/urandom of=/data/file2.bin bs=1M count=2048 status=none
sync
echo "---- files on /data ----"
ls -lh /data
echo "---- checksums ----"
sha256sum /data/file1.bin /data/file2.bin
```

✅ **Expected:** `file1.bin` at **1.0G** and `file2.bin` at **2.0G**, plus **two** SHA-256 lines.
📝 **Copy both checksums.** The `file1.bin` checksum should match the one from Step 4.

---

## Step 7 — Take Snapshot 2 (incremental)

Repeat Step 5 on the same data disk with:

| Field | Value |
|---|---|
| Name | `snap2-incremental` |
| **Snapshot type** | **Incremental** |

---

## Step 8 — Look at both snapshots in the portal

1. Search for **Snapshots** and open it.
2. Click each snapshot and look at its **Overview** page.

| | `snap1-baseline` | `snap2-incremental` |
|---|---|---|
| Snapshot type | Incremental | Incremental |
| Size | 32 GiB | 32 GiB |
| Source disk | `vm-snaplab_DataDisk_0` | `vm-snaplab_DataDisk_0` |

> ⚠️ **Why both say 32 GiB:** the portal shows the size of the **disk the snapshot can restore**, not the data it stores or what you're billed for. The portal has no page that shows a snapshot's stored data, so Step 9 measures it directly.

---

## Step 9 — VERIFY: prove Snapshot 2 holds only the incremental data

Azure lets you read which data blocks a snapshot holds through a temporary read-only link, and lets you ask for **only the blocks that changed between two snapshots**. You'll measure three numbers:

| Measurement | What it answers |
|---|---|
| **A.** Data in Snapshot 1 | How big is the baseline? |
| **B.** Data visible through Snapshot 2 | What would a **full** backup of the disk now contain? |
| **C.** Data changed from Snapshot 1 → Snapshot 2 | What Snapshot 2 **actually** stores and bills |

### 9.1 Generate a read-only URL for each snapshot

For **`snap1-baseline`**:

1. Open the snapshot. In the left menu, go to **Settings** → **Snapshot export**.
2. Set **URL expiry (seconds)** to `3600`.
3. Click **Generate URL**, then **copy** the URL. Paste it into Notepad labeled **SAS1**.

Repeat for **`snap2-incremental`** and label it **SAS2**.

> Treat these URLs like passwords: anyone with them can read the disk's contents until they expire or you cancel them (Step 9.5).

### 9.2 Open Cloud Shell

1. Click the **Cloud Shell** icon (**>_**) in the portal's top bar.
2. Choose **Bash**. If asked about storage, pick the option that needs no storage account (or accept the defaults).

### 9.3 Create the verification script

Paste this whole block into Cloud Shell and press **Enter**:

```bash
cat > page_ranges.py <<'EOF'
#!/usr/bin/env python3
"""
Sum the data stored in an Azure managed-disk snapshot, using the Get Page Ranges API.

  page_ranges.py <SNAPSHOT_URL>                 -> all data blocks in the snapshot
  page_ranges.py <SNAPSHOT_URL> <PREVIOUS_URL>  -> only blocks changed since PREVIOUS
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

### 9.4 Run the verification

Replace the placeholders with the two URLs you copied. **Keep the double quotes** — the URLs contain `&` characters.

```bash
SAS1="<paste SAS1 URL here>"
SAS2="<paste SAS2 URL here>"

echo "A. Data in Snapshot 1 (baseline):"
./page_ranges.py "$SAS1"

echo "B. Data visible through Snapshot 2 (what a FULL backup would copy):"
./page_ranges.py "$SAS2"

echo "C. Data changed between Snapshot 1 and Snapshot 2 (what Snapshot 2 really stores):"
./page_ranges.py "$SAS2" "$SAS1"
```

Example output (your exact bytes will differ slightly because of filesystem metadata):

```
A. Data in Snapshot 1 (baseline):
1,190,526,976 bytes  (1.11 GiB)
B. Data visible through Snapshot 2 (what a FULL backup would copy):
3,345,883,136 bytes  (3.12 GiB)
C. Data changed between Snapshot 1 and Snapshot 2 (what Snapshot 2 really stores):
2,155,356,160 bytes  (2.01 GiB)
```

### Reading the proof

```
 B (full view of disk)          ████████████████████████████████  3.12 GiB
 C (Snapshot 2 really stores)   █████████████████████             2.01 GiB
 A (Snapshot 1 baseline)        ███████████                       1.11 GiB

                       A  +  C  =  B
                    1.11 + 2.01 = 3.12 GiB  ✔
```

| Check | Result | Meaning |
|---|---|---|
| A ≈ 1 GiB | ✔ | Snapshot 1 holds `file1.bin` |
| C ≈ 2 GiB | ✔ | Snapshot 2 holds only `file2.bin` |
| C < B | ✔ | Snapshot 2 is **not** a full copy (a full copy would be ≈ 3 GiB) |
| A + C ≈ B | ✔ | Snapshot 2 reuses Snapshot 1's blocks for `file1.bin` |

### 9.5 Revoke the URLs

On each snapshot, go back to **Settings** → **Snapshot export** and click **Cancel export**.

---

## Step 10 — VERIFY: Snapshot 2 is still a complete restore point

Incremental doesn't mean partial. A disk built from **Snapshot 2 alone** contains both files.

**Create a disk from Snapshot 2**

1. Open **`snap2-incremental`** and click **+ Create disk** at the top.
2. **Disk name:** `disk-restored-from-snap2`. Resource group and region: same as the lab. Any SKU.
3. Click **Review + create** → **Create**.

**Attach it to the VM**

1. Open **`vm-snaplab`** → **Settings** → **Disks**.
2. Click **Attach existing disks**, choose **`disk-restored-from-snap2`**, set **LUN** to **1**.
3. Click **Save** (or **Apply**).

**Check the files** — **Run command** → **RunShellScript**:

```bash
# Mount the restored disk (LUN 1) read-only and verify both files
mkdir -p /restored
mount -o ro /dev/disk/azure/scsi1/lun1 /restored
echo "---- files on restored disk ----"
ls -lh /restored
echo "---- checksums ----"
sha256sum /restored/file1.bin /restored/file2.bin
```

✅ **Expected:** both files listed, and both checksums **match the ones from Step 6**. A disk created from a ~2 GiB incremental snapshot has all ~3 GiB of data; Azure supplies `file1.bin` from Snapshot 1's blocks behind the scenes.

---

## Step 11 — What this saves in storage and money

Using the measured values from Step 9 and an illustrative snapshot price of **$0.05 per GiB per month** (check your region's real rate on the [Managed Disks pricing page](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)):

| | Full snapshots | Incremental snapshots |
|---|---|---|
| Snapshot 1 | 1.11 GiB | 1.11 GiB |
| Snapshot 2 | 3.12 GiB (full copy) | **2.01 GiB** (delta only) |
| **Total stored** | **4.23 GiB** | **3.12 GiB** |
| **Monthly cost** | $0.21 | $0.16 |
| **Saved** | — | **1.11 GiB · 26%** |

The lab saves "only" 26% because it adds 2 GiB to a disk holding 1 GiB — a 200% change, far more than real workloads. The amount saved always equals the data that **didn't** change.

### At realistic scale

A production disk with **500 GiB used** and **20 GiB changed per day**:

| Backups kept | Full snapshots | Incremental snapshots | Storage saved | Monthly saved (@ $0.05) |
|---|---|---|---|---|
| 2 | 1,000 GiB | 520 GiB | 48.0% | $24.00 |
| 7 (one week) | 3,500 GiB | 620 GiB | 82.3% | $144.00 |
| 30 (one month) | 15,000 GiB | 1,080 GiB | 92.8% | $696.00 |

```
Full storage        = Backups × Used
Incremental storage = Used + (Backups − 1) × Changed
```

At 30 daily restore points that's about **$8,350 per year saved on one disk**.

### Confirm on your bill (optional)

After 24–48 hours: search **Cost Management** → **Cost analysis**. Set the scope to your subscription, add the filter **Resource group = `rg-incremental-snapshot-lab`**, and group by **Resource**. `snap2-incremental` is charged for roughly 2 GiB, not 3 GiB.

---

## Step 12 — Clean up

1. Open **Resource groups** → **`rg-incremental-snapshot-lab`**.
2. Click **Delete resource group**, type the name to confirm, and click **Delete**.

This removes the VM, all disks and both snapshots.

---

## Quick reference: data and verification scripts

| When | Where | Script |
|---|---|---|
| Format & mount | VM → Run command | Step 3 |
| Generate 1 GiB | VM → Run command | Step 4 |
| Generate 2 GiB more | VM → Run command | Step 6 |
| Measure snapshot data (A, B, C) | Cloud Shell | Steps 9.3–9.4 |
| Verify restore | VM → Run command | Step 10 |

## Troubleshooting

| Problem | Fix |
|---|---|
| `ERROR: /data is not mounted` | The VM rebooted or Step 3 didn't finish. Run only the last three lines of Step 3 (`mkdir`, `mount`, `df`) — **don't** re-run `mkfs`, it would erase the disk. |
| `file1.bin: No such file or directory` in Step 6 | Step 4 didn't write to the data disk. Delete any snapshots, then on the VM's **Disks** page detach and delete the data disk, attach a **new** empty 32 GiB disk at LUN 0, and redo Steps 3–7. Deleting `file2.bin` isn't enough — its blocks stay on the disk and would end up in Snapshot 1. |
| No **Snapshot type** option, or only *Full* | Make sure you started from the **disk** page (Step 5), and that the disk isn't an Ultra or Premium SSD v2 disk in an unsupported setup. Use Standard SSD for this lab. |
| `HTTP Error 403` in Cloud Shell | The URL expired or was cancelled, or a character was lost when pasting. Generate it again (Step 9.1). |
| `HTTP Error 400` for measurement C | Both snapshots must be **Incremental** and come from the **same** disk. |
| C is noticeably bigger than 2 GiB | The filesystem was still initializing; Step 3 must include `lazy_itable_init=0,lazy_journal_init=0`. |
| Restored disk won't mount in Step 10 | Wait a minute after attaching, then run the Step 10 script again. Check the disk shows LUN 1 on the VM's **Disks** page. |
| Run command seems stuck | Only one Run command can run at a time. Wait for the previous one to finish, then retry. |

## How it works

- Azure tracks which 512-byte pages of a managed disk change between snapshots.
- The **first** incremental snapshot stores every used page.
- Each **later** incremental snapshot stores only the pages changed since the previous one, and refers to earlier snapshots for everything else.
- Incremental snapshots are always kept on Standard storage and billed per GiB actually stored.
- Deleting Snapshot 1 is safe: Azure keeps the pages Snapshot 2 still needs, so Snapshot 2 stays fully restorable.

## References

- [Create an incremental snapshot for managed disks](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-incremental-snapshots)
- [Run scripts in a Linux VM with Run command](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command)
- [Get Page Ranges REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/get-page-ranges)
- [Azure Managed Disks pricing](https://azure.microsoft.com/en-us/pricing/details/managed-disks/)
