# Module 09 – Create an Azure Network Interface (NIC)

## Objective
Create a NIC in a subnet and associate a public IP.

Prerequisites: resource group, VNet, subnet, and public IP exist.

Bash:
```bash
RG="rg-azcli-training"
VNET="vnet-azcli"
SUBNET="snet-app"
PIP="pip-azcli-vm"
NIC="nic-azcli-vm"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$VNET = "vnet-azcli"
$SUBNET = "snet-app"
$PIP = "pip-azcli-vm"
$NIC = "nic-azcli-vm"
```

## 1. Create NIC
```bash
az network nic create \
  --resource-group "$RG" \
  --name "$NIC" \
  --location "centralindia" \
  --vnet-name "$VNET" \
  --subnet "$SUBNET" \
  --public-ip-address "$PIP"
```

## 2. Verify
```bash
az network nic show --resource-group "$RG" --name "$NIC" --output json
az network nic list --resource-group "$RG" --output table
```

## Teaching points
- A NIC connects a VM to a VNet subnet.
- Private IP configuration is attached to the NIC.
- A public IP can be associated with a NIC IP configuration.
- NSGs can be associated with a NIC or subnet.

## Lab task
Inspect the NIC JSON and identify its subnet ID, private IP, and public IP association.
