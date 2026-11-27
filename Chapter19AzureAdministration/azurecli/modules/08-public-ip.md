# Module 08 – Create an Azure Public IP Address

## Objective
Create a Standard SKU static public IP and inspect it.

Bash:
```bash
RG="rg-azcli-training"
LOCATION="centralindia"
PIP="pip-azcli-vm"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$LOCATION = "centralindia"
$PIP = "pip-azcli-vm"
```

## 1. Create
```bash
az network public-ip create \
  --resource-group "$RG" \
  --name "$PIP" \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static
```

## 2. Show assigned IP
```bash
az network public-ip show --resource-group "$RG" --name "$PIP" --query "{Name:name,IP:ipAddress,SKU:sku.name}" --output table
```

## 3. List public IPs
```bash
az network public-ip list --resource-group "$RG" --output table
```

## Teaching points
- Standard public IPs use static allocation.
- Creating a public IP does not automatically expose a VM; it must be associated with a supported resource such as a NIC IP configuration or load balancer.
- A public IP is not a substitute for NSG rules.
- Restrict management access to trusted source IPs.

## Lab task
Create a second public IP and compare the SKU and allocation method.
