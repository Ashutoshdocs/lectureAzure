# Module 14 – End-to-End Azure CLI Infrastructure Project

## Scenario
Deploy a simple Linux web VM environment using individual Azure resources created through Azure CLI.

## Architecture
```text
Resource Group
  ├── Virtual Network (10.30.0.0/16)
  │     └── Subnet (10.30.1.0/24)
  ├── Network Security Group (SSH restricted to your IP)
  ├── Public IP
  ├── Network Interface
  └── Linux Virtual Machine
        └── Managed OS disk
```

## Step 1 – Set variables

Bash:
```bash
LOCATION="centralindia"
RG="rg-azcli-project"
VNET="vnet-project"
SUBNET="snet-web"
NSG="nsg-project"
PIP="pip-project"
NIC="nic-project"
VM="vm-project"
```

PowerShell:
```powershell
$LOCATION = "centralindia"
$RG = "rg-azcli-project"
$VNET = "vnet-project"
$SUBNET = "snet-web"
$NSG = "nsg-project"
$PIP = "pip-project"
$NIC = "nic-project"
$VM = "vm-project"
```

## Step 2 – Create resource group and network
```bash
az group create -n "$RG" -l "$LOCATION"
az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" --address-prefixes 10.30.0.0/16
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --address-prefixes 10.30.1.0/24
```

## Step 3 – Create NSG and SSH rule
Replace `<YOUR_PUBLIC_IP>/32` with your own public IP CIDR.
```bash
az network nsg create -g "$RG" -n "$NSG" -l "$LOCATION"
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-SSH-My-IP --priority 1000 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "<YOUR_PUBLIC_IP>/32" --destination-port-ranges 22
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --network-security-group "$NSG"
```

## Step 4 – Create public IP and NIC
```bash
az network public-ip create -g "$RG" -n "$PIP" -l "$LOCATION" --sku Standard --allocation-method Static
az network nic create -g "$RG" -n "$NIC" -l "$LOCATION" --vnet-name "$VNET" --subnet "$SUBNET" --public-ip-address "$PIP"
```

## Step 5 – Create SSH key and VM
```bash
ssh-keygen -t ed25519 -f ~/.ssh/azcli_project_key -C "azcli-project"
az vm create -g "$RG" -n "$VM" -l "$LOCATION" --nics "$NIC" --image Ubuntu2404 --size Standard_B1s --admin-username azureuser --ssh-key-values ~/.ssh/azcli_project_key.pub --authentication-type ssh
```

## Step 6 – Verify
```bash
az vm list -g "$RG" --show-details -o table
az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv
```

## Step 7 – Connect
```bash
ssh -i ~/.ssh/azcli_project_key azureuser@<PUBLIC_IP>
```

## Assessment checklist
- [ ] Resource group created in the selected region.
- [ ] VNet and subnet use non-overlapping valid ranges.
- [ ] NSG SSH rule is restricted to the learner's public IP.
- [ ] Public IP and NIC are associated correctly.
- [ ] VM is deployed and SSH access works.
- [ ] Learner can explain the purpose of every resource.

## Extension challenges
1. Add an HTTP rule and install Nginx on the VM.
2. Create and attach a 32-GB data disk.
3. Enable system-assigned managed identity on the VM.
4. Assign Reader access to the VM identity at the resource group scope.
5. Deploy the same lab in another region and compare the resource configuration.
