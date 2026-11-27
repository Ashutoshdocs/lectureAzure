# Practical 1 – Create a Linux VM using individual Bicep components

## Learning objectives

By the end of this practical, students should be able to:
- Identify the Azure resources required for a Linux VM.
- Keep each component in its own Bicep module.
- Pass values between a parent Bicep file and modules.
- Understand module outputs and dependencies.
- Preview a deployment with `what-if`.

## Architecture

The parent file `main.bicep` calls separate modules to create:

1. Virtual Network and subnet
2. Network Security Group and subnet association
3. Public IP address
4. Network Interface
5. Ubuntu Linux Virtual Machine

The VM is in **Central US**. For a simple classroom demo, SSH (TCP 22) is allowed from the Internet. Restrict `adminSourceAddressPrefix` to your public IP/CIDR before deploying in a real environment. A public IP is used in this first practical to keep the component demonstration straightforward; Practical 2 uses Bastion and a private VM.

## Files

| File | Purpose |
|---|---|
| `main.bicep` | Parent template; wires the modules together |
| `modules/network.bicep` | VNet and subnet |
| `modules/nsg.bicep` | NSG and SSH rule |
| `modules/public-ip.bicep` | Static public IP |
| `modules/nic.bicep` | NIC attached to subnet, NSG and public IP |
| `modules/vm.bicep` | Ubuntu VM |
| `parameters.example.json` | Example non-secret parameters |

## 1. Set variables

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"

RG="rg-bicep-vm-components"
az group create --name "$RG" --location centralus
```

Create an SSH key pair if you do not already have one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/azure_bicep_lab -N ""
```

## 2. Review and validate the template

```bash
az bicep build --file main.bicep
az deployment group validate \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/azure_bicep_lab.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"
```

Replace `<YOUR_PUBLIC_IP>` with your public IPv4 address. Do not use `*` for a production NSG rule.

## 3. Preview and deploy

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/azure_bicep_lab.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"

az deployment group create \
  --name "deploy-vm-components" \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters adminUsername="azureadmin" \
               sshPublicKey="$(cat ~/.ssh/azure_bicep_lab.pub)" \
               adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"
```

## 4. Connect to the VM

Get the public IP:

```bash
VM_IP=$(az deployment group show -g "$RG" -n deploy-vm-components \
  --query properties.outputs.vmPublicIp.value -o tsv)
echo "$VM_IP"
ssh -i ~/.ssh/azure_bicep_lab azureadmin@"$VM_IP"
```

## 5. Observe the resources

```bash
az resource list --resource-group "$RG" --output table
az vm show --resource-group "$RG" --name vm-bicep-components \
  --query "{name:name,size:hardwareProfile.vmSize,os:storageProfile.imageReference.offer}"
```

## Teaching discussion

- Why is the NIC a separate resource from the VM?
- Which module output supplies the subnet ID to the NIC module?
- Why does the VM module depend on the NIC?
- What changes if the public IP module is removed?
- Why should SSH source IP be restricted?

## Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```

Only delete the resource group if it is dedicated to this practical.
