# Azure VM Image Demo: Nginx → Versioned Gallery Images → Bicep Deployments

This demo walks through the full image lifecycle on Azure:

1. Build a VM, install **Nginx**, and publish a web page.
2. Capture it as image **1.0.0** in an **Azure Compute Gallery**.
3. Make a change and capture **1.1.0**. Make another change and capture **1.2.0**.
4. Give every image a **version number**, and tag the newest one **`latest=true`** each time (older ones get `latest=false`).
5. After each capture, use **Bicep** to deploy a fresh VM from the image end to end and prove that it serves the right page.

The Bicep code takes the image as a JSON object **with no version**. It always gets the **latest** image.

---

## Table of contents

- [How "latest" works](#how-latest-works)
- [Repository layout](#repository-layout)
- [Quick start (whole demo with the scripts)](#quick-start-whole-demo-with-the-scripts)
- [Prerequisites](#prerequisites)
- [Step 0 – Variables](#step-0--variables)
- [Step 1 – Manual network setup (RG, VNet, Subnet)](#step-1--manual-network-setup-rg-vnet-subnet)
- [Step 2 – Create the Compute Gallery and image definition](#step-2--create-the-compute-gallery-and-image-definition)
- [Step 3 – Helper scripts](#step-3--helper-scripts)
- [Step 4 – Image 1.0.0 (Nginx + web page)](#step-4--image-100-nginx--web-page)
- [Step 5 – Image 1.1.0 (change #1)](#step-5--image-110-change-1)
- [Step 6 – Image 1.2.0 (change #2)](#step-6--image-120-change-2)
- [Bicep files](#bicep-files)
- [Deploying with Bicep (end-to-end proof)](#deploying-with-bicep-end-to-end-proof)
- [Proving an older version still works](#proving-an-older-version-still-works)
- [Verification checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

---

## How "latest" works

There are two layers, and they always agree:

| Layer | What it does | Who uses it |
|---|---|---|
| **Azure "latest" resolution** | When a VM refers to an image **definition** ID (`.../galleries/<g>/images/<def>`) and leaves out `/versions/<x>`, Azure uses the **highest version number** that isn't flagged `excludeFromLatest`. | Bicep and `az vm create` |
| **`latest=true` tag** | After each capture, `tag-latest.sh` sets `latest=true` on the highest version and `latest=false` on all others. | People, the portal, audits, scripts |

The tag script uses the same rule as Azure: highest semantic version. That means the version marked `latest=true` is always the one Bicep deploys. Every Bicep deployment also **outputs the exact version it used** (`imageVersionUsed`), so you can check this.

> Pure Bicep can't query tags at deploy time. Leaving the version out of the reference is the native, supported way to get "always latest", and the tag mirrors it.

---

## Repository layout

```
VmImageBicepAutomation/
├── README.md
├── .gitignore
├── scripts/
│   ├── env.sh                    # shared variables – source this first
│   ├── 01-create-network.sh      # RG + VNet + Subnet (manual, not Bicep)
│   ├── 02-create-gallery.sh      # Compute Gallery + image definition
│   ├── v1-install-nginx.sh       # image 1.0.0 – install nginx + page
│   ├── v2-change.sh              # image 1.1.0 – new page + /health
│   ├── v3-change.sh              # image 1.2.0 – header + about page + tools
│   ├── build-image.sh            # builder VM → change script → capture → retag (one command)
│   ├── capture.sh                # generalize VM → create gallery version → retag
│   ├── tag-latest.sh             # mark newest version latest=true, others false
│   ├── deploy-bicep.sh           # Bicep deploy from LATEST + PASS/FAIL proof
│   ├── deploy-pinned-version.sh  # prove an older version still deploys
│   ├── verify.sh                 # versions, tags, and which VM got which version
│   └── cleanup.sh                # delete demo VMs, or everything
└── bicep/
    ├── main.bicep                # entry point (subscription scope)
    ├── vm.bicep                  # NSG, Public IP, NIC, VM from gallery image
    └── main.bicepparam           # YOUR values: RG, VNet, subnet, VM name, disk, image JSON
```

---

## Quick start (whole demo with the scripts)

Run from inside the `VmImageBicepAutomation` folder. First set `subscriptionId` in `bicep/main.bicepparam` (and change any names you like in `scripts/env.sh`).

```bash
cd VmImageBicepAutomation
chmod +x scripts/*.sh
source ./scripts/env.sh                 # every new shell

./scripts/01-create-network.sh          # RG, VNet, Subnet (manual, once)
./scripts/02-create-gallery.sh          # gallery + image definition (once)

# Image 1.0.0 → prove with Bicep
./scripts/build-image.sh 1.0.0 scripts/v1-install-nginx.sh marketplace
./scripts/deploy-bicep.sh vm-web-v1     # expect PASS, version 1.0.0

# Image 1.1.0 → prove with Bicep
./scripts/build-image.sh 1.1.0 scripts/v2-change.sh
./scripts/deploy-bicep.sh vm-web-v2     # expect PASS, version 1.1.0

# Image 1.2.0 → prove with Bicep
./scripts/build-image.sh 1.2.0 scripts/v3-change.sh
./scripts/deploy-bicep.sh vm-web-v3     # expect PASS, version 1.2.0

# Older version still works
./scripts/deploy-pinned-version.sh 1.0.0

./scripts/verify.sh                     # tags + which VM used which version
./scripts/cleanup.sh vms                # or: ./scripts/cleanup.sh all
```

The sections below explain every step and show the same commands done by hand.

---

## Prerequisites

- Azure CLI **2.60+** (`az version`) with Bicep (`az bicep upgrade`)
- Logged in: `az login` then `az account set --subscription "<SUB_ID>"`
- Bash (Linux, macOS, WSL, or Azure Cloud Shell)
- An SSH key pair (`~/.ssh/id_rsa.pub`). `--generate-ssh-keys` creates one if you don't have it.

---

## Step 0 – Variables

These are in `scripts/env.sh` – run `source ./scripts/env.sh` in every shell session. The contents:

```bash
export SUB_ID=$(az account show --query id -o tsv)
export LOCATION="centralindia"

# Network (created manually in Step 1)
export RG="rg-image-demo"
export VNET="vnet-image-demo"
export SUBNET="snet-vms"

# Gallery
export GALLERY="galImageDemo"            # letters, digits, _ and . only
export IMAGE_DEF="nginx-ubuntu2204"
export PUBLISHER="DemoOrg"
export OFFER="NginxWeb"
export SKU="ubuntu2204-nginx"

export ADMIN_USER="azureuser"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"   # read by main.bicepparam
```

---

## Step 1 – Manual network setup (RG, VNet, Subnet)

Bicep does **not** create these. Create them once, by hand:

```bash
az group create -n $RG -l $LOCATION

az network vnet create \
  -g $RG -n $VNET \
  --address-prefixes 10.50.0.0/16 \
  --subnet-name $SUBNET \
  --subnet-prefixes 10.50.1.0/24
```

---

## Step 2 – Create the Compute Gallery and image definition

```bash
az sig create -g $RG --gallery-name $GALLERY -l $LOCATION

az sig image-definition create \
  -g $RG --gallery-name $GALLERY \
  --gallery-image-definition $IMAGE_DEF \
  --publisher $PUBLISHER --offer $OFFER --sku $SKU \
  --os-type Linux \
  --os-state Generalized \
  --hyper-v-generation V2 \
  --features SecurityType=TrustedLaunch
```

> The definition is **Generalized**, so each VM deployed from it gets its own hostname, admin user, and SSH key from Bicep.
> It is **TrustedLaunch** because the builder VMs are Trusted Launch (Gen2). The Bicep VM uses the same setting.

---

## Step 3 – Helper scripts

These files are already in the `scripts/` folder. Their contents are shown here for reference.

### `scripts/v1-install-nginx.sh` (image 1.0.0)

```bash
#!/bin/bash
set -euo pipefail

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

# Site config: SSI lets the page show the hostname of the VM serving it
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    location / { try_files $uri $uri/ =404; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.0.0</title></head>
<body style="font-family:sans-serif;background:#1f4e79;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.0.0</h2>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

echo "1.0.0" > /var/www/html/version.txt

nginx -t
systemctl enable nginx
systemctl restart nginx
```

### `scripts/v2-change.sh` (image 1.1.0)

Change #1: new page design and a `/health` endpoint.

```bash
#!/bin/bash
set -euo pipefail

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    location / { try_files $uri $uri/ =404; }
    location = /health { default_type text/plain; return 200 "OK\n"; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.1.0</title></head>
<body style="font-family:sans-serif;background:#2e7d32;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.1.0</h2>
  <p>Change #1: new theme + <code>/health</code> endpoint</p>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

echo "1.1.0" > /var/www/html/version.txt

nginx -t
systemctl restart nginx
```

### `scripts/v3-change.sh` (image 1.2.0)

Change #2: custom response header, an About page, and an extra package.

```bash
#!/bin/bash
set -euo pipefail

DEBIAN_FRONTEND=noninteractive apt-get install -y htop

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    ssi on;
    add_header X-Image-Version "1.2.0" always;
    location / { try_files $uri $uri/ =404; }
    location = /health { default_type text/plain; return 200 "OK\n"; }
}
EOF

cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html><head><title>Image Demo v1.2.0</title></head>
<body style="font-family:sans-serif;background:#6a1b9a;color:#fff;text-align:center;padding-top:80px">
  <h1>Azure VM Image Demo</h1>
  <h2>Image version: 1.2.0</h2>
  <p>Change #2: <code>X-Image-Version</code> header + <a style="color:#fff" href="/about.html">About page</a> + htop</p>
  <p>Served by: <!--#echo var="hostname" --></p>
</body></html>
EOF

cat > /var/www/html/about.html <<'EOF'
<!doctype html>
<html><body style="font-family:sans-serif;padding:40px">
  <h1>About</h1>
  <p>This VM was deployed from Azure Compute Gallery image <b>1.2.0</b> via Bicep.</p>
</body></html>
EOF

echo "1.2.0" > /var/www/html/version.txt

nginx -t
systemctl restart nginx
```

### `scripts/tag-latest.sh`

Marks the highest version `latest=true` and every other version `latest=false`.

```bash
#!/bin/bash
set -euo pipefail
: "${RG:?}" "${GALLERY:?}" "${IMAGE_DEF:?}"

# All versions as "name id", sorted by semantic version (same rule Azure uses)
mapfile -t VERSIONS < <(az sig image-version list \
  -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
  --query "[?publishingProfile.excludeFromLatest!=\`true\`].[name,id]" -o tsv | sort -V -k1,1)

if [ ${#VERSIONS[@]} -eq 0 ]; then echo "No versions found"; exit 1; fi

NEWEST_ID=$(echo "${VERSIONS[-1]}" | awk '{print $2}')
NEWEST_NAME=$(echo "${VERSIONS[-1]}" | awk '{print $1}')

for row in "${VERSIONS[@]}"; do
  id=$(echo "$row" | awk '{print $2}')
  if [ "$id" == "$NEWEST_ID" ]; then
    az tag update --resource-id "$id" --operation Merge --tags latest=true  -o none
  else
    az tag update --resource-id "$id" --operation Merge --tags latest=false -o none
  fi
done

echo "Latest image version is now: $NEWEST_NAME"
az sig image-version list -g "$RG" -r "$GALLERY" -i "$IMAGE_DEF" \
  --query "[].{version:name, latestTag:tags.latest, state:provisioningState}" -o table
```

### `scripts/capture.sh`

Usage: `./scripts/capture.sh <builder-vm-name> <version>`

```bash
#!/bin/bash
set -euo pipefail
: "${RG:?}" "${GALLERY:?}" "${IMAGE_DEF:?}" "${LOCATION:?}"

VM_NAME="$1"
VERSION="$2"

echo ">> Deprovisioning $VM_NAME (removes machine-specific data and the build user)"
az vm run-command invoke -g "$RG" -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "sudo waagent -deprovision+user -force" -o none

echo ">> Deallocating and generalizing"
az vm deallocate -g "$RG" -n "$VM_NAME"
az vm generalize -g "$RG" -n "$VM_NAME"

VM_ID=$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv)

echo ">> Creating gallery image version $VERSION"
az sig image-version create \
  -g "$RG" --gallery-name "$GALLERY" \
  --gallery-image-definition "$IMAGE_DEF" \
  --gallery-image-version "$VERSION" \
  --virtual-machine "$VM_ID" \
  --target-regions "$LOCATION" \
  --replica-count 1 \
  --storage-account-type Standard_LRS \
  --tags latest=true imageVersion="$VERSION" sourceVm="$VM_NAME"

echo ">> Re-tagging: newest = latest=true, others = latest=false"
"$(dirname "$0")/tag-latest.sh"

echo ">> Deleting builder VM (a generalized VM can't be started again)"
az vm delete -g "$RG" -n "$VM_NAME" --yes --force-deletion none
```

Make them executable:

```bash
chmod +x scripts/*.sh
```

---

## Step 4 – Image 1.0.0 (Nginx + web page)

### 4.1 Create the builder VM from the Ubuntu marketplace image

```bash
az vm create \
  -g $RG -n vm-builder-v1 \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --security-type TrustedLaunch \
  --vnet-name $VNET --subnet $SUBNET \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg-rule SSH

az vm open-port -g $RG -n vm-builder-v1 --port 80 --priority 1010
```

### 4.2 Install Nginx and the page

```bash
az vm run-command invoke -g $RG -n vm-builder-v1 \
  --command-id RunShellScript --scripts @scripts/v1-install-nginx.sh
```

### 4.3 Check the page before capturing

```bash
IP=$(az vm show -d -g $RG -n vm-builder-v1 --query publicIps -o tsv)
curl -s http://$IP/version.txt     # → 1.0.0
```

### 4.4 Capture as 1.0.0 and tag it latest

```bash
./scripts/capture.sh vm-builder-v1 1.0.0
```

Expected:

```
Version    LatestTag    State
---------  -----------  ---------
1.0.0      true         Succeeded
```

### 4.5 Prove it with Bicep

Follow [Deploying with Bicep](#deploying-with-bicep-end-to-end-proof) with `vmName=vm-web-v1`. You should see `imageVersionUsed = 1.0.0`.

---

## Step 5 – Image 1.1.0 (change #1)

Each change starts from the **current latest image**. That is a realistic "patch the golden image" flow, and it proves the previous image boots.

```bash
IMAGE_ID=$(az sig image-definition show -g $RG -r $GALLERY -i $IMAGE_DEF --query id -o tsv)

az vm create \
  -g $RG -n vm-builder-v2 \
  --image "$IMAGE_ID" \
  --size Standard_B2s \
  --security-type TrustedLaunch \
  --vnet-name $VNET --subnet $SUBNET \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg-rule SSH
az vm open-port -g $RG -n vm-builder-v2 --port 80 --priority 1010

az vm run-command invoke -g $RG -n vm-builder-v2 \
  --command-id RunShellScript --scripts @scripts/v2-change.sh

IP=$(az vm show -d -g $RG -n vm-builder-v2 --query publicIps -o tsv)
curl -s http://$IP/version.txt     # → 1.1.0
curl -s http://$IP/health          # → OK

./scripts/capture.sh vm-builder-v2 1.1.0
```

Expected:

```
Version    LatestTag    State
---------  -----------  ---------
1.0.0      false        Succeeded
1.1.0      true         Succeeded
```

Prove it with Bicep using `vmName=vm-web-v2`. You should get `imageVersionUsed = 1.1.0`.

---

## Step 6 – Image 1.2.0 (change #2)

```bash
IMAGE_ID=$(az sig image-definition show -g $RG -r $GALLERY -i $IMAGE_DEF --query id -o tsv)

az vm create \
  -g $RG -n vm-builder-v3 \
  --image "$IMAGE_ID" \
  --size Standard_B2s \
  --security-type TrustedLaunch \
  --vnet-name $VNET --subnet $SUBNET \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg-rule SSH
az vm open-port -g $RG -n vm-builder-v3 --port 80 --priority 1010

az vm run-command invoke -g $RG -n vm-builder-v3 \
  --command-id RunShellScript --scripts @scripts/v3-change.sh

IP=$(az vm show -d -g $RG -n vm-builder-v3 --query publicIps -o tsv)
curl -sI http://$IP/ | grep -i x-image-version   # → X-Image-Version: 1.2.0

./scripts/capture.sh vm-builder-v3 1.2.0
```

Expected:

```
Version    LatestTag    State
---------  -----------  ---------
1.0.0      false        Succeeded
1.1.0      false        Succeeded
1.2.0      true         Succeeded
```

Prove it with Bicep using `vmName=vm-web-v3`. You should get `imageVersionUsed = 1.2.0`.

---

## Bicep files

Three files in `bicep/`:

| File | Purpose |
|---|---|
| `main.bicep` | Entry point. Deployed at **subscription scope** so you can choose the target resource group in the parameter file. Calls `vm.bicep`. |
| `vm.bicep` | Creates the NSG, Public IP (optional), NIC, data disk (optional), and VM. Uses the **existing** VNet/subnet and the **gallery image definition** (no version means latest). |
| `main.bicepparam` | **The only file you edit.** Resource group, VNet, subnet, VM name, size, disk sizes, and the image JSON (without a version). |

### `bicep/main.bicep`

```bicep
targetScope = 'subscription'

// ---------- Types ----------
@sealed() // rejects extra properties, so nobody can add a "version" field
type imageInfoType = {
  @description('Subscription that holds the Compute Gallery')
  subscriptionId: string
  @description('Resource group that holds the Compute Gallery')
  resourceGroupName: string
  @description('Compute Gallery name')
  galleryName: string
  @description('Image definition name. NO version: Azure picks the latest.')
  imageDefinitionName: string
}

// ---------- Parameters ----------
@description('Azure region for the VM resources')
param location string

@description('Existing resource group the VM is deployed into')
param vmResourceGroupName string

@description('Resource group of the existing VNet (defaults to the VM RG)')
param vnetResourceGroupName string = vmResourceGroupName

@description('Existing VNet name')
param vnetName string

@description('Existing subnet name')
param subnetName string

@description('VM name')
param vmName string

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Admin username')
param adminUsername string = 'azureuser'

@secure()
@description('SSH public key for the admin user')
param sshPublicKey string

@minValue(30)
@description('OS disk size in GB (must be >= image OS disk size)')
param osDiskSizeGB int = 64

@allowed([ 'Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS' ])
param osDiskType string = 'StandardSSD_LRS'

@minValue(0)
@description('Data disk size in GB. 0 = no data disk')
param dataDiskSizeGB int = 0

@allowed([ 'Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS' ])
param dataDiskType string = 'StandardSSD_LRS'

@allowed([ 'TrustedLaunch', 'Standard' ])
@description('Must match the image definition security type')
param securityType string = 'TrustedLaunch'

@description('Create a public IP for the VM')
param createPublicIp bool = true

@description('Source IP/CIDR allowed to reach SSH (22) and HTTP (80)')
param allowedSourceIp string = '*'

@description('Gallery image info. NO version: the latest is always used.')
param imageInfo imageInfoType

param tags object = {}

// ---------- Module ----------
module vm 'vm.bicep' = {
  name: 'vm-${vmName}'
  scope: resourceGroup(vmResourceGroupName)
  params: {
    location: location
    vnetResourceGroupName: vnetResourceGroupName
    vnetName: vnetName
    subnetName: subnetName
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    osDiskSizeGB: osDiskSizeGB
    osDiskType: osDiskType
    dataDiskSizeGB: dataDiskSizeGB
    dataDiskType: dataDiskType
    securityType: securityType
    createPublicIp: createPublicIp
    allowedSourceIp: allowedSourceIp
    imageInfo: imageInfo
    tags: tags
  }
}

// ---------- Outputs ----------
output vmId string = vm.outputs.vmId
output publicIp string = vm.outputs.publicIp
output privateIp string = vm.outputs.privateIp
output imageReferenceUsed string = vm.outputs.imageReferenceUsed
output imageVersionUsed string = vm.outputs.imageVersionUsed
```

### `bicep/vm.bicep`

```bicep
@sealed()
type imageInfoType = {
  subscriptionId: string
  resourceGroupName: string
  galleryName: string
  imageDefinitionName: string
}

param location string
param vnetResourceGroupName string
param vnetName string
param subnetName string
param vmName string
param vmSize string
param adminUsername string
@secure()
param sshPublicKey string
param osDiskSizeGB int
param osDiskType string
param dataDiskSizeGB int
param dataDiskType string
param securityType string
param createPublicIp bool
param allowedSourceIp string
param imageInfo imageInfoType
param tags object

// ---------- Existing network (created manually) ----------
var subnetId = resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)

// ---------- Gallery image: DEFINITION id, no /versions/ → Azure uses the LATEST version ----------
var galleryImageId = resourceId(
  imageInfo.subscriptionId,
  imageInfo.resourceGroupName,
  'Microsoft.Compute/galleries/images',
  imageInfo.galleryName,
  imageInfo.imageDefinitionName
)

// ---------- NSG ----------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${vmName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// ---------- Public IP (optional) ----------
resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (createPublicIp) {
  name: '${vmName}-pip'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ---------- NIC ----------
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: createPublicIp ? { id: pip.id } : null
        }
      }
    ]
  }
}

// ---------- VM ----------
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: union(tags, { sourceImageDefinition: imageInfo.imageDefinitionName })
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: securityType == 'TrustedLaunch' ? {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    } : null
    storageProfile: {
      imageReference: {
        id: galleryImageId // <-- no version = latest
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        managedDisk: { storageAccountType: osDiskType }
        deleteOption: 'Delete'
      }
      dataDisks: dataDiskSizeGB > 0 ? [
        {
          name: '${vmName}-datadisk0'
          lun: 0
          createOption: 'Empty'
          diskSizeGB: dataDiskSizeGB
          managedDisk: { storageAccountType: dataDiskType }
          deleteOption: 'Delete'
        }
      ] : []
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true } // managed storage
    }
  }
}

// ---------- Outputs ----------
output vmId string = vm.id
output publicIp string = pip.?properties.ipAddress ?? 'none'
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output imageReferenceUsed string = galleryImageId
@description('The exact gallery version Azure resolved as "latest" at deploy time')
output imageVersionUsed string = vm.properties.storageProfile.imageReference.exactVersion
```

### `bicep/main.bicepparam`

**This is the only file you edit.** The image JSON has **no version**.

```bicep
using 'main.bicep'

// ---------- Placement ----------
param location              = 'centralindia'
param vmResourceGroupName   = 'rg-image-demo'      // existing (manual)
param vnetResourceGroupName = 'rg-image-demo'      // existing (manual)
param vnetName              = 'vnet-image-demo'    // existing (manual)
param subnetName            = 'snet-vms'           // existing (manual)

// ---------- VM ----------
param vmName        = 'vm-web-01'
param vmSize        = 'Standard_B2s'
param adminUsername = 'azureuser'
param sshPublicKey  = readEnvironmentVariable('SSH_PUBLIC_KEY') // export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
param securityType  = 'TrustedLaunch'

// ---------- Disks ----------
param osDiskSizeGB   = 64
param osDiskType     = 'StandardSSD_LRS'
param dataDiskSizeGB = 0                 // e.g. 128 to attach a data disk
param dataDiskType   = 'StandardSSD_LRS'

// ---------- Network access ----------
param createPublicIp  = true
param allowedSourceIp = '*'              // better: 'x.x.x.x/32' (your IP)

// ---------- Image (NO VERSION: always uses the latest) ----------
param imageInfo = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'   // az account show --query id -o tsv
  resourceGroupName: 'rg-image-demo'
  galleryName: 'galImageDemo'
  imageDefinitionName: 'nginx-ubuntu2204'
}

param tags = {
  project: 'vm-image-demo'
  deployedBy: 'bicep'
}
```

---

## Deploying with Bicep (end-to-end proof)

Run this after **each** capture (Steps 4.5, 5, and 6). Use a **new VM name** each time, for example `vm-web-v1`, `vm-web-v2`, `vm-web-v3`. You can edit `vmName` in the param file, or override it on the command line as shown.

```bash
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
VM=vm-web-v1          # then vm-web-v2, vm-web-v3

# Optional: lint and preview
az bicep build -f bicep/main.bicep
az deployment sub what-if -l $LOCATION \
  -f bicep/main.bicep -p bicep/main.bicepparam -p vmName=$VM

# Deploy
az deployment sub create \
  -n "deploy-$VM" -l $LOCATION \
  -f bicep/main.bicep \
  -p bicep/main.bicepparam \
  -p vmName=$VM

# Read outputs
az deployment sub show -n "deploy-$VM" \
  --query "properties.outputs.{publicIp:publicIp.value, imageVersionUsed:imageVersionUsed.value}" -o table
```

### Prove the deployed VM matches the `latest=true` image

```bash
IP=$(az deployment sub show -n "deploy-$VM" --query properties.outputs.publicIp.value -o tsv)
USED=$(az deployment sub show -n "deploy-$VM" --query properties.outputs.imageVersionUsed.value -o tsv)
TAGGED=$(az sig image-version list -g $RG -r $GALLERY -i $IMAGE_DEF \
          --query "[?tags.latest=='true'].name | [0]" -o tsv)
SERVED=$(curl -s http://$IP/version.txt)

echo "Bicep used : $USED"
echo "Tagged     : $TAGGED"
echo "Page serves: $SERVED"
[ "$USED" == "$TAGGED" ] && [ "$USED" == "$SERVED" ] && echo "PASS ✅" || echo "FAIL ❌"
```

Open `http://<publicIp>/` in a browser. The page shows the image version and the hostname of the new VM (for example `vm-web-v2`), so you can see it is a fresh VM built from the image.

### Expected results

| After capturing | Deploy VM | `imageVersionUsed` | `/version.txt` | Extra check |
|---|---|---|---|---|
| 1.0.0 | `vm-web-v1` | 1.0.0 | 1.0.0 | Blue page |
| 1.1.0 | `vm-web-v2` | 1.1.0 | 1.1.0 | Green page, `/health` → OK |
| 1.2.0 | `vm-web-v3` | 1.2.0 | 1.2.0 | Purple page, `X-Image-Version: 1.2.0`, `/about.html` |

The **same Bicep files and the same parameter file** deployed a newer image each time. Nothing changed except which gallery version was newest.

---

## Proving an older version still works

Bicep is built to use only the latest. To show that the older versions are still deployable, pin a version directly with the CLI:

```bash
OLD_ID=$(az sig image-version show -g $RG -r $GALLERY -i $IMAGE_DEF -e 1.0.0 --query id -o tsv)

az vm create -g $RG -n vm-pinned-100 \
  --image "$OLD_ID" --size Standard_B2s --security-type TrustedLaunch \
  --vnet-name $VNET --subnet $SUBNET \
  --admin-username $ADMIN_USER --generate-ssh-keys \
  --public-ip-sku Standard --nsg-rule SSH
az vm open-port -g $RG -n vm-pinned-100 --port 80 --priority 1010

curl -s http://$(az vm show -d -g $RG -n vm-pinned-100 --query publicIps -o tsv)/version.txt   # → 1.0.0
```

---

## Verification checklist

```bash
# 1. All versions, their tags, and replication state
az sig image-version list -g $RG -r $GALLERY -i $IMAGE_DEF \
  --query "[].{version:name, latest:tags.latest, excludeFromLatest:publishingProfile.excludeFromLatest, state:provisioningState}" -o table

# 2. Exactly one version tagged latest=true
az sig image-version list -g $RG -r $GALLERY -i $IMAGE_DEF --query "length([?tags.latest=='true'])"   # → 1

# 3. Which version each deployed VM actually got
for v in vm-web-v1 vm-web-v2 vm-web-v3; do
  echo "$v → $(az vm show -g $RG -n $v --query storageProfile.imageReference.exactVersion -o tsv)"
done
```

---

## Troubleshooting

| Problem | Cause / fix |
|---|---|
| `Changing property 'imageReference' is not allowed` | You redeployed to an **existing** VM name. Image changes need a new VM. Use a new `vmName` or delete the old VM first. |
| `SecurityType ... does not match` when creating a VM or version | The image definition is `TrustedLaunch`. Keep `securityType = 'TrustedLaunch'` in the param file and `--security-type TrustedLaunch` on builder VMs. |
| `The value of parameter imageInfo is invalid` / unexpected property `version` | That's on purpose: `@sealed()` blocks a `version` field. Remove it. |
| Disk size error | `osDiskSizeGB` must be **≥** the image OS disk size (30 GB for Ubuntu 22.04). |
| Bicep deployed an older version than expected | The new version is still replicating (`provisioningState != Succeeded`) or is marked `excludeFromLatest`. Wait for `Succeeded` and check the table in the verification checklist. |
| `readEnvironmentVariable` error | Run `export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"` in the same shell before deploying. |
| Page doesn't load | Check that the NSG allows port 80 from your IP (`allowedSourceIp`) and run `az vm run-command invoke ... --scripts "systemctl status nginx"`. |
| Inline `-p vmName=...` ignored with `.bicepparam` | Update Azure CLI (`az upgrade`), or just edit `vmName` in `main.bicepparam`. |

---

## Cleanup

```bash
# Remove demo VMs (NIC, OS disk, and data disk are deleted with the VM via deleteOption)
for v in vm-web-v1 vm-web-v2 vm-web-v3 vm-pinned-100; do
  az vm delete -g $RG -n $v --yes 2>/dev/null
done

# Or delete everything, including the gallery and the network
az group delete -n $RG --yes --no-wait
```
