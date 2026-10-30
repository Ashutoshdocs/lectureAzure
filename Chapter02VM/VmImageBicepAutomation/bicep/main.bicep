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
