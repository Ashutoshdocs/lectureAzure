# Azure Linux VM with Bicep

This template creates a Linux Azure VM and the networking resources required to connect to it.

## Resources created

- Azure Linux VM
- Virtual Network (VNet)
- Subnet
- Network Security Group (NSG)
- SSH inbound NSG rule
- Network Interface (NIC)
- Standard Static Public IP (optional)
- Ubuntu 24.04 LTS image

The template uses **SSH public-key authentication** and does not enable password authentication.

## Files

```text
azure-vm-bicep/
├── main.bicep
├── parameters.json
└── README.md
```

## Prerequisites

Install and sign in to Azure CLI:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

Check Bicep support:

```bash
az bicep version
```

If needed:

```bash
az bicep install
```

Generate an SSH key if you do not already have one:

```bash
ssh-keygen -t ed25519 -C "azure-vm"
```

Display the public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the complete output into `parameters.json` under `adminSshPublicKey`.

> Security note: `parameters.json` contains a public SSH key, which is normally safe to share, but never put a private key such as `id_ed25519` into the Bicep parameters.

## 1. Create a resource group

```bash
az group create \
  --name rg-bicep-vm-demo \
  --location centralindia
```

## 2. Update parameters

Edit:

```text
parameters.json
```

At minimum, change:

```json
"adminSshPublicKey": {
  "value": "REPLACE_WITH_YOUR_SSH_PUBLIC_KEY"
}
```

You can also change VM size, location, VM name, VNet CIDR, subnet CIDR, NSG name, and other values.

## 3. Validate the Bicep template

```bash
az deployment group validate \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters @parameters.json
```

## 4. Preview changes

```bash
az deployment group what-if \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters @parameters.json
```

## 5. Deploy

```bash
az deployment group create \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters @parameters.json
```

Get the public IP:

```bash
az vm show \
  --resource-group rg-bicep-vm-demo \
  --name demo-vm \
  --show-details \
  --query publicIps \
  --output tsv
```

Connect:

```bash
ssh azureadmin@<PUBLIC_IP>
```

## Parameterization

The important values are parameters instead of being hard-coded:

| Parameter | Purpose | Example |
|---|---|---|
| `location` | Azure region | `centralindia` |
| `vmName` | VM name | `demo-vm` |
| `vmSize` | VM SKU | `Standard_B2s` |
| `adminUsername` | Linux username | `azureadmin` |
| `adminSshPublicKey` | SSH public key | `ssh-ed25519 ...` |
| `vnetName` | VNet name | `demo-vm-vnet` |
| `vnetAddressPrefix` | VNet CIDR | `10.0.0.0/16` |
| `subnetName` | Subnet name | `default` |
| `subnetAddressPrefix` | Subnet CIDR | `10.0.0.0/24` |
| `nsgName` | NSG name | `demo-vm-nsg` |
| `publicIpName` | Public IP name | `demo-vm-pip` |
| `nicName` | NIC name | `demo-vm-nic` |
| `sshSourceAddressPrefix` | Allowed SSH source | `*` or your IP/CIDR |
| `createPublicIp` | Create public IP | `true` / `false` |
| `imagePublisher` | Image publisher | `Canonical` |
| `imageOffer` | Image offer | `ubuntu-24_04-lts` |
| `imageSku` | Image SKU | `server` |
| `imageVersion` | Image version | `latest` |

## Recommended SSH security

For a lab, `*` allows SSH from anywhere:

```json
"sshSourceAddressPrefix": {
  "value": "*"
}
```

For a more secure deployment, restrict it to your public IP:

```json
"sshSourceAddressPrefix": {
  "value": "203.0.113.10/32"
}
```

Replace `203.0.113.10/32` with your actual public IP/CIDR.

You can find your public IP with:

```bash
curl -4 ifconfig.me
```

## Deploy without a parameters file

You can override parameters directly:

```bash
az deployment group create \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters vmName=my-vm \
  --parameters vmSize=Standard_B2s \
  --parameters adminUsername=azureadmin \
  --parameters adminSshPublicKey="$(cat ~/.ssh/id_ed25519.pub)" \
  --parameters location=centralindia
```

## Useful examples

### Change VM size

```bash
az deployment group create \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters @parameters.json \
  --parameters vmSize=Standard_D2s_v5
```

### Change region

```bash
az deployment group create \
  --resource-group rg-bicep-vm-demo \
  --template-file main.bicep \
  --parameters @parameters.json \
  --parameters location=eastus
```

### Create a VM without a public IP

Set:

```json
"createPublicIp": {
  "value": false
}
```

In this mode, connect using Azure Bastion, VPN/ExpressRoute, or another private connectivity method.

## Clean up

Delete the complete resource group:

```bash
az group delete \
  --name rg-bicep-vm-demo \
  --yes \
  --no-wait
```

## Architecture

```text
                    Internet
                       |
                       | SSH :22
                       v
              +-------------------+
              |  Public IP        |
              |  Static Standard  |
              +---------+---------+
                        |
                        v
                 +-------------+
                 | NIC         |
                 +------+------+
                        |
                        v
              +-------------------+
              | NSG               |
              | Allow SSH :22     |
              +---------+---------+
                        |
                        v
        +--------------------------------+
        | VNet 10.0.0.0/16              |
        |                                |
        |  +--------------------------+  |
        |  | Subnet 10.0.0.0/24      |  |
        |  |                          |  |
        |  |       Linux VM           |  |
        |  |       Ubuntu 24.04       |  |
        |  +--------------------------+  |
        +--------------------------------+
```

## Teaching flow

A useful way to explain this template:

1. **Parameters** make the template reusable.
2. **NSG** controls inbound SSH traffic.
3. **VNet/Subnet** provide private networking.
4. **Public IP** provides optional internet reachability.
5. **NIC** connects the VM to the subnet and public IP.
6. **VM** uses the Ubuntu Marketplace image.
7. **SSH key authentication** avoids VM passwords.
8. **Outputs** expose the VM name, IP and SSH command.

## Important production considerations

This is designed as a reusable lab/teaching template. For production, consider:

- Restricting SSH to trusted source IPs.
- Using Azure Bastion instead of exposing SSH publicly.
- Using Azure Managed Identity.
- Applying Azure Policy and resource locks where appropriate.
- Using availability zones or VM Scale Sets for workloads requiring higher availability.
- Using private endpoints/private networking where applicable.
- Storing sensitive deployment values in Azure Key Vault rather than source-controlled files.
- Pinning image versions instead of using `latest` when reproducibility is required.
