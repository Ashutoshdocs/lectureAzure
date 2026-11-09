# Module 10 – Network Security Groups (NSGs)

## Objective
Create an NSG, add an inbound SSH rule, and associate the NSG with a subnet.

> Security: Replace `<YOUR_PUBLIC_IP>/32` with your current trusted public IP. Do not open SSH to the entire internet in a production environment.

Bash:
```bash
RG="rg-azcli-training"
LOCATION="centralindia"
VNET="vnet-azcli"
SUBNET="snet-app"
NSG="nsg-azcli"
```

PowerShell:
```powershell
$RG = "rg-azcli-training"
$LOCATION = "centralindia"
$VNET = "vnet-azcli"
$SUBNET = "snet-app"
$NSG = "nsg-azcli"
```

## 1. Create NSG
```bash
az network nsg create --resource-group "$RG" --name "$NSG" --location "$LOCATION"
```

## 2. Add SSH rule restricted to your IP
```bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG" \
  --name "Allow-SSH-From-My-IP" \
  --priority 1000 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "<YOUR_PUBLIC_IP>/32" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 22
```

## 3. Associate NSG with subnet
```bash
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --network-security-group "$NSG"
```

## 4. Verify rules and association
```bash
az network nsg show --resource-group "$RG" --name "$NSG" --output json
az network nsg rule list --resource-group "$RG" --nsg-name "$NSG" --output table
az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" --name "$SUBNET" --query networkSecurityGroup.id --output tsv
```

## Teaching points
- NSGs contain inbound and outbound security rules.
- Lower numerical priority values are evaluated first.
- An NSG can be associated with a subnet or NIC.
- Effective access depends on all relevant network controls and routing; an allow rule alone does not guarantee connectivity.

## Lab task
Add an HTTP rule on TCP 80 with a suitable priority. Discuss whether the VM actually needs public HTTP access.
