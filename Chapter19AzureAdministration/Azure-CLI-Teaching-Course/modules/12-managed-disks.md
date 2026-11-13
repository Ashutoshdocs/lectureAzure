# Module 12 – Create and Attach a Managed Data Disk

## Objective
Create a managed disk, attach it to a VM, and verify the attachment.

Prerequisite: a VM exists and is running or deallocated as required by the operation.

## 1. Create a data disk
```bash
az disk create \
  --resource-group "rg-azcli-training" \
  --name "disk-azcli-data01" \
  --location "centralindia" \
  --size-gb 32 \
  --sku Standard_LRS \
  --hyper-v-generation V2
```

## 2. Attach disk to VM
```bash
az vm disk attach \
  --resource-group "rg-azcli-training" \
  --vm-name "vm-azcli-linux" \
  --name "disk-azcli-data01" \
  --lun 0
```

## 3. Verify from Azure
```bash
az vm show --resource-group "rg-azcli-training" --name "vm-azcli-linux" --query "storageProfile.dataDisks" --output json
az disk show --resource-group "rg-azcli-training" --name "disk-azcli-data01" --output table
```

## 4. Verify inside Linux VM
```bash
lsblk
sudo fdisk -l
```

A newly attached disk may need partitioning, filesystem creation, and mounting. These operations modify the disk. In a real environment, check carefully that you select the new empty disk, not the OS disk.

Example only – after positively identifying the new device (for example `/dev/sdc`):
```bash
sudo parted /dev/sdc --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 /dev/sdc1
sudo mkdir -p /data
sudo mount /dev/sdc1 /data
df -h
```

For persistence after reboot, configure `/etc/fstab` using the filesystem UUID (`sudo blkid`) rather than relying on a device name.

## 5. Detach
```bash
az vm disk detach --resource-group "rg-azcli-training" --vm-name "vm-azcli-linux" --name "disk-azcli-data01"
```

## Teaching points
- Managed disks are Azure storage resources used by VMs.
- OS disks and data disks have different purposes.
- Azure attachment and Linux filesystem formatting/mounting are separate steps.
- Formatting the wrong disk causes data loss.
