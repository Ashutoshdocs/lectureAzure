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
