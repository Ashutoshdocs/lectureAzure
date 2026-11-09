# Module 06 – Create an Azure Virtual Network

## Objective
Create a VNet with an address space and inspect its properties.

Bash:
```bash
RG="rg-azcli-training"
LOCATION="centralindia"
VNET="vnet-azcli"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$LOCATION = "centralindia"
$VNET = "vnet-azcli"
```

## 1. Create VNet
```bash
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOCATION" \
  --address-prefixes 10.10.0.0/16
```

## 2. Show VNet
```bash
az network vnet show --resource-group "$RG" --name "$VNET" --output json
```

## 3. List VNets
```bash
az network vnet list --resource-group "$RG" --output table
```

## Teaching points
- A VNet is a private network boundary in Azure.
- The address space is an IP range from which subnet ranges are allocated.
- Avoid overlapping address ranges when planning peering or hybrid connectivity.
- A subnet is created inside a VNet; it is not a separate VNet.

## Lab task
Create a second VNet using a non-overlapping range such as `10.20.0.0/16`. Compare the address spaces.
