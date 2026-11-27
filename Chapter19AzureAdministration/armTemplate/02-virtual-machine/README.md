# Practical 2 – Deploy an Ubuntu Linux VM using an ARM Template

## Learning objectives

- Deploy a VM using an ARM JSON template.
- Understand dependencies between VNet, NSG, public IP, NIC and VM.
- Use an SSH public key rather than a hard-coded password.
- Preview and deploy the infrastructure.

## Architecture

The template creates:
- Virtual Network and subnet
- Network Security Group with SSH restricted to the supplied CIDR
- Standard static Public IP
- Network Interface
- Ubuntu 24.04 Linux VM

## 1. Prepare

```bash
az login
RG="rg-arm-vm"
az group create --name "$RG" --location centralindia

ssh-keygen -t ed25519 -f ~/.ssh/arm_vm_key -N ""
```

## 2. Set the parameters

Replace `<YOUR_PUBLIC_IP>/32` with your current public IPv4 address and use the SSH public key file:

```bash
ADMIN_IP="<YOUR_PUBLIC_IP>/32"
SSH_KEY="$(cat ~/.ssh/arm_vm_key.pub)"
```

## 3. Validate and preview

```bash
az deployment group validate \
  --resource-group "$RG" \
  --template-file vm-template.json \
  --parameters adminUsername="azureuser" \
               sshPublicKey="$SSH_KEY" \
               adminSourceAddressPrefix="$ADMIN_IP"

az deployment group what-if \
  --resource-group "$RG" \
  --template-file vm-template.json \
  --parameters adminUsername="azureuser" \
               sshPublicKey="$SSH_KEY" \
               adminSourceAddressPrefix="$ADMIN_IP"
```

## 4. Deploy

```bash
az deployment group create \
  --name arm-vm-deployment \
  --resource-group "$RG" \
  --template-file vm-template.json \
  --parameters adminUsername="azureuser" \
               sshPublicKey="$SSH_KEY" \
               adminSourceAddressPrefix="$ADMIN_IP"
```

## 5. Connect

```bash
VM_IP=$(az deployment group show -g "$RG" -n arm-vm-deployment \
  --query properties.outputs.vmPublicIp.value -o tsv)

ssh -i ~/.ssh/arm_vm_key azureuser@"$VM_IP"
```

## 6. Observe dependencies

The NIC references the subnet, NSG and public IP. The VM references the NIC. ARM uses resource references and `dependsOn` to order deployment.

## Teaching discussion

- Why is the NIC a separate resource?
- Why should SSH source IP be restricted?
- What is the purpose of `dependsOn`?
- Which values are parameters and which are fixed resource names?

## Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```
