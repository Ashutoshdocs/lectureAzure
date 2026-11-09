# Module 11 – Create and Manage an Azure Linux Virtual Machine

## Objective
Create a Linux VM, connect with SSH, inspect it, and manage its power state.

Prerequisites: resource group, VNet, subnet, NSG, public IP, and NIC from earlier modules. Ensure the NSG SSH rule allows your trusted public IP.

## 1. Create an SSH key pair (if needed)

Bash:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/azcli_training_key -C "azcli-training"
```

PowerShell (OpenSSH client installed):
```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\azcli_training_key" -C "azcli-training"
```

Keep the private key private. Only the `.pub` public key is supplied to Azure.

## 2. Create VM using the existing NIC

Bash:
```bash
az vm create \
  --resource-group "rg-azcli-training" \
  --name "vm-azcli-linux" \
  --location "centralindia" \
  --nics "nic-azcli-vm" \
  --image "Ubuntu2404" \
  --size "Standard_B1s" \
  --admin-username "azureuser" \
  --ssh-key-values "$HOME/.ssh/azcli_training_key.pub" \
  --authentication-type ssh
```

PowerShell:
```powershell
az vm create --resource-group "rg-azcli-training" --name "vm-azcli-linux" --location "centralindia" --nics "nic-azcli-vm" --image "Ubuntu2404" --size "Standard_B1s" --admin-username "azureuser" --ssh-key-values "$HOME\.ssh\azcli_training_key.pub" --authentication-type ssh
```

If the chosen size or image is unavailable in the selected region/subscription, query available sizes and images, then choose a supported option.

## 3. Verify VM and public IP
```bash
az vm list --resource-group "rg-azcli-training" --show-details --output table
az vm show --resource-group "rg-azcli-training" --name "vm-azcli-linux" --output json
az network public-ip show --resource-group "rg-azcli-training" --name "pip-azcli-vm" --query ipAddress --output tsv
```

## 4. Connect using SSH
```bash
ssh -i ~/.ssh/azcli_training_key azureuser@<PUBLIC_IP>
```

PowerShell:
```powershell
ssh -i "$HOME\.ssh\azcli_training_key" azureuser@<PUBLIC_IP>
```

## 5. VM power operations
```bash
az vm stop --resource-group "rg-azcli-training" --name "vm-azcli-linux"
az vm deallocate --resource-group "rg-azcli-training" --name "vm-azcli-linux"
az vm start --resource-group "rg-azcli-training" --name "vm-azcli-linux"
az vm restart --resource-group "rg-azcli-training" --name "vm-azcli-linux"
```

## 6. Resize (check availability first)
```bash
az vm list-vm-resize-options --resource-group "rg-azcli-training" --name "vm-azcli-linux" --output table
az vm resize --resource-group "rg-azcli-training" --name "vm-azcli-linux" --size "Standard_B2s"
```

## Teaching points
- VM creation can create dependent resources automatically, but this lab creates the network components separately to teach each resource.
- SSH public key is installed on the VM; the private key remains with the administrator.
- `stop` and `deallocate` are different. Deallocation releases compute allocation and is generally the intended action to stop VM compute charges.
- Disks, networking, and other attached resources may continue to incur charges.

## Lab task
Create the VM, connect over SSH, run `hostname`, `ip address`, and `lsb_release -a`, then deallocate the VM.
