# Azure Shared Managed Disk Demo – 2 VMs, MySQL + Web App on One Disk

One **Azure shared managed disk** (Premium SSD, `maxShares=2`) is attached to
**vm01** and **vm02**. Everything that matters lives on that disk:

```
/mnt/shared            (shared disk, ext4, label "shareddata")
├── mysql/             MySQL data directory  (bind-mounted to /var/lib/mysql)
├── app/app.py         Flask frontend
├── app/app.env        DB credentials
├── config/debian.cnf  MySQL maintenance creds (same on both nodes)
└── ACTIVE_NODE        name of the VM currently owning the disk
```

The app shows **which VM is serving** the page and a table of notes stored in
MySQL. Stop vm01 → activate vm02 → the same page and the same notes come back,
now served by vm02.

> **Important – active/passive only.** ext4 is not a cluster filesystem, so only
> **one VM mounts the disk at a time**. The scripts enforce this with the
> `ACTIVE_NODE` marker. Never run `activate.sh --force` while the other VM is
> still running with the disk mounted – that corrupts the filesystem.
> (Production would use Pacemaker + SCSI-PR fencing, or a cluster FS like GFS2.)

---

## Files

| File | Where it runs | Purpose |
|---|---|---|
| `config.env` | laptop | Names, region, zone, sizes – edit first |
| `01-create-vms.sh` | laptop / Cloud Shell | RG, VNet, NSG (22, 80), vm01 + vm02 in same zone |
| `02-create-attach-shared-disk.sh` | laptop / Cloud Shell | Create shared disk, attach to both VMs (LUN 0, cache None) |
| `03-node-setup.sh` | **both** VMs | Install MySQL + Flask, disable MySQL autostart, add `demo-app` service |
| `04-init-shared-disk.sh` | **vm01 only, once** | Format disk, move MySQL data + app onto it, create DB |
| `activate.sh` | the VM taking over | Mount disk, start MySQL + app |
| `deactivate.sh` | the VM giving up | Stop app + MySQL, unmount disk |
| `fix-db-user.sh` | active VM | Repair "Access denied for user 'demo'" – resync DB user with `app.env` |
| `05-failover-demo.sh` | laptop / Cloud Shell | Deallocate vm01, activate vm02 remotely |
| `06-failback.sh` | laptop / Cloud Shell | Start vm01, cleanly deactivate vm02, activate vm01 |
| `app/app.py` | (copied to shared disk) | Frontend application |

---

## Prerequisites

- Azure subscription + Azure CLI (`az login`) – Cloud Shell works.
- Region that supports availability zones (default `centralindia`).
- VM size with Premium SSD support (default `Standard_D2s_v5`).

---

## Order of Steps

### Step 0 – Configure
```bash
cd shared-disk-demo
nano config.env          # change RG / region / zone if needed
chmod +x *.sh
```

### Step 1 – Create the 2 VMs (laptop)
```bash
./01-create-vms.sh
```
Note the two public IPs printed at the end.

<details><summary>Creating the VMs yourself (Portal) instead</summary>

Create **vm01** and **vm02** with: Ubuntu 22.04, size `Standard_D2s_v5`,
**same region and same availability zone** (e.g. Zone 1), same VNet/subnet,
inbound ports 22 and 80 open, admin user `azureuser`. Then put the names you
used into `config.env`.
</details>

### Step 2 – Create the shared disk and attach to both (laptop)
```bash
./02-create-attach-shared-disk.sh
```
The output must show `maxShares: 2` and both VMs under `attachedTo`.

<details><summary>Doing it in the Portal instead</summary>

1. **Disks → Create**: same RG, region, **same zone** as the VMs,
   Premium SSD, 256 GiB, **Advanced → Enable shared disk = Yes, Max shares = 2**.
2. **vm01 → Disks → Attach existing disk** → `shared-disk01`, LUN **0**,
   Host caching **None** → Save.
3. Repeat for **vm02** (also LUN 0, caching None).

The disk can be attached to running VMs – you can create the VMs now and attach later.
</details>

### Step 3 – Copy the kit to both VMs (laptop)
```bash
VM01=<vm01-public-ip>; VM02=<vm02-public-ip>
scp -r ../shared-disk-demo azureuser@$VM01:~
scp -r ../shared-disk-demo azureuser@$VM02:~
```

### Step 4 – Node setup on **both** VMs
```bash
ssh azureuser@$VM01  'cd shared-disk-demo && sudo ./03-node-setup.sh'
ssh azureuser@$VM02  'cd shared-disk-demo && sudo ./03-node-setup.sh'
```
Each should list `lun0` under `/dev/disk/azure/scsi1/`.

### Step 5 – Initialise the shared disk on **vm01 only**
```bash
ssh azureuser@$VM01  'cd shared-disk-demo && sudo ./04-init-shared-disk.sh'
```
⚠️ Run once, on one VM. It formats the disk (and refuses if already formatted).

### Step 6 – Use the app on vm01
Open `http://<vm01-public-ip>/`

- Badge shows **vm01**.
- Add a few notes (e.g. "written on vm01").

### Step 7 – Failover: stop vm01, run on vm02

**Option A – one command from laptop**
```bash
./05-failover-demo.sh            # deallocates vm01, activates vm02
```

**Option B – manually (good for showing each step live)**
```bash
# 1. Stop vm01 (Portal → vm01 → Stop, or:)
az vm deallocate -g rg-shareddisk-demo -n vm01

# 2. On vm02
ssh azureuser@$VM02
cd shared-disk-demo
sudo ./activate.sh            # refuses: "Disk is marked ACTIVE on 'vm01'"
sudo ./activate.sh --force    # vm01 is stopped, so taking over is safe
```

Open `http://<vm02-public-ip>/`

- Badge now shows **vm02**.
- All the notes written on vm01 are still there → same MySQL data, same disk.
- Add a note "written on vm02".

### Step 8 – (Optional) Fail back to vm01

**Option A – one command from laptop**
```bash
./06-failback.sh                 # starts vm01, deactivates vm02, activates vm01
```
It only activates vm01 after vm02 reports it has released the disk. If vm02 is
already stopped, it activates vm01 with `--force`.

**Option B – manually**
```bash
az vm start -g rg-shareddisk-demo -n vm01
ssh azureuser@$VM02 'cd shared-disk-demo && sudo ./deactivate.sh'   # clean release
ssh azureuser@$VM01 'cd shared-disk-demo && sudo ./activate.sh'     # no --force needed
```
vm01 does **not** grab the disk on boot (MySQL and the app are not enabled at
startup) – it only becomes active when you run `activate.sh`.

### Step 9 – Cleanup
```bash
az group delete -n rg-shareddisk-demo --yes --no-wait
```

---

## Demo talking points

- **What moved?** Nothing was copied. vm02 mounted the same disk, MySQL
  ran crash recovery on the data vm01 left behind, and the app code was read
  from the same disk.
- **Clean vs crash failover:** `deactivate.sh` = planned switch (no `--force`).
  Deallocating vm01 = simulated crash; ext4 replays its journal and InnoDB
  recovers committed transactions.
- **Different IPs:** each VM keeps its own public IP. For a single endpoint,
  put both VMs behind an Azure Load Balancer with health probe `/health`
  (returns 200 only on the active node).

## Useful checks

```bash
# On a VM
cat /mnt/shared/ACTIVE_NODE
mount | grep -E "shared|mysql"
sudo systemctl status mysql demo-app
curl -s localhost/health
sudo journalctl -u demo-app -n 50

# From laptop
az disk show -g rg-shareddisk-demo -n shared-disk01 --query managedByExtended
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Shared disk not found at /dev/disk/azure/scsi1/lun0` | Disk not attached, or attached on a LUN other than 0 |
| `az disk create` fails on `--zone` | Region has no zones – remove `--zone` from scripts and VM create (VMs and disk must still match) |
| `label shareddata not found` on vm02 | Run `sudo partprobe /dev/disk/azure/scsi1/lun0` or reboot vm02 |
| Page shows `Access denied for user 'demo'@'localhost'` | MySQL is serving the local datadir. Run `sudo ./deactivate.sh && sudo ./activate.sh`; if it persists, `sudo ./fix-db-user.sh` |
| Page shows "Database error" | `sudo systemctl status mysql`; check `/var/log/mysql/error.log` |
| MySQL won't start on vm02 | Both VMs must have the same MySQL version (`mysqld --version`); setup script holds the package |
