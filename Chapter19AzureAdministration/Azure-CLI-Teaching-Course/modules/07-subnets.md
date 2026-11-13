# Module 07 – Create and Manage Subnets

## Objective
Create a subnet inside an existing VNet and verify its address range.

Bash:
```bash
RG="rg-azcli-training"
VNET="vnet-azcli"
SUBNET="snet-app"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$VNET = "vnet-azcli"
$SUBNET = "snet-app"
```

## 1. Create subnet
```bash
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --address-prefixes 10.10.1.0/24
```

## 2. List subnets
```bash
az network vnet subnet list --resource-group "$RG" --vnet-name "$VNET" --output table
```

## 3. Show one subnet
```bash
az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" --name "$SUBNET" --output json
```

## Teaching points
- The subnet prefix must fit within the VNet address space.
- Subnet prefixes in the same VNet must not overlap.
- Azure reserves some addresses in each subnet; not every address is assignable to a VM.
- Some Azure services require dedicated or delegated subnets.

## Lab task
Create `snet-web` with `10.10.2.0/24` and `snet-db` with `10.10.3.0/24`.
