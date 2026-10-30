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
