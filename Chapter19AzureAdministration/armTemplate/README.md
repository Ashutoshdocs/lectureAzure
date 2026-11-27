# Azure ARM Templates – Lecture Practicals

This package contains four independent folders for teaching Azure Resource Manager (ARM) templates using JSON.

## Folder structure

1. `01-arm-template-basics/` – understand ARM template structure, schema, contentVersion, resources, properties, outputs and deployment commands.
2. `02-virtual-machine/` – deploy an Ubuntu Linux VM with VNet, subnet, NSG, public IP and NIC using an ARM JSON template.
3. `03-storage-account/` – deploy a StorageV2 account and two private Blob containers.
4. `04-template-and-parameter-files/` – separate reusable template JSON from parameter JSON, use parameter types/defaults/allowed values/secure parameters, and deploy with different parameter files.

Each folder has its own README.md with detailed explanations, commands, verification and cleanup.

## Prerequisites

- Azure subscription and Azure CLI.
- PowerShell, Bash, or Azure Cloud Shell.
- Permission to create resources in a dedicated resource group.
- For the VM practical, an SSH public key and a trusted source IP/CIDR for SSH.

## General deployment pattern

```bash
az login
az group create --name rg-arm-lecture --location centralindia

az deployment group validate \
  --resource-group rg-arm-lecture \
  --template-file template.json \
  --parameters @parameters.json

az deployment group what-if \
  --resource-group rg-arm-lecture \
  --template-file template.json \
  --parameters @parameters.json

az deployment group create \
  --name arm-lecture-deployment \
  --resource-group rg-arm-lecture \
  --template-file template.json \
  --parameters @parameters.json
```

## Important safety

- Use dedicated lab resource groups.
- Restrict SSH to your own public IP; do not use `*` in production.
- Never store passwords, private keys, or other secrets in source-controlled parameter files.
- VM, disk and public IP resources can incur charges.
- Review `what-if` output before deployment.
- Delete only resource groups dedicated to these labs.
