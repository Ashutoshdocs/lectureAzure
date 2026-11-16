// =============================================================================
// Module: vm.bicep
// Creates a NIC (optional public IP) and a Virtual Machine with a
// System-Assigned Managed Identity. Admin credentials come in as @secure()
// parameters (resolved from Key Vault by the caller via getSecret()).
// =============================================================================

@description('Name of the virtual machine.')
param vmName string

@description('Azure region for the VM and its NIC.')
param location string

@description('VM size, e.g. Standard_B2s, Standard_D2s_v5.')
param vmSize string

@description('Operating system type of the image.')
@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

@description('Marketplace image reference: { publisher, offer, sku, version }.')
param imageReference object

@description('Admin username (secure because it is read from Key Vault).')
@secure()
param adminUsername string

@description('Admin password (read from Key Vault).')
@secure()
param adminPassword string

@description('Resource ID of the subnet the NIC is attached to.')
param subnetId string

@description('Managed disk SKU for the OS disk.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'StandardSSD_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param osDiskType string = 'StandardSSD_LRS'

@description('OS disk size in GB.')
param osDiskSizeGB int = 64

@description('Create and attach a public IP. Keep false and use Bastion/VPN where possible.')
param enablePublicIp bool = false

@description('Availability zone ("1", "2", "3") or empty string for no zone.')
param zone string = ''

@description('Tags applied to every resource in this module.')
param tags object = {}

var nicName = 'nic-${vmName}'
var pipName = 'pip-${vmName}'
var osDiskName = 'osdisk-${vmName}'
var zones = empty(zone) ? [] : [
  zone
]

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (enablePublicIp) {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: zones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: enablePublicIp ? {
            id: pip.id
          } : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  zones: zones
  identity: {
    type: 'SystemAssigned' // <-- Managed Identity enabled
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      // Windows computer names are limited to 15 characters
      computerName: osType == 'Windows' ? take(vmName, 15) : vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: osType == 'Linux' ? {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      } : null
      windowsConfiguration: osType == 'Windows' ? {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      } : null
    }
    storageProfile: {
      imageReference: imageReference
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true // managed boot diagnostics storage
      }
    }
  }
}

@description('Resource ID of the VM.')
output vmId string = vm.id

@description('Name of the VM.')
output vmName string = vm.name

@description('Object (principal) ID of the VM system-assigned managed identity.')
output principalId string = vm.identity.principalId

@description('Private IP address of the VM.')
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
