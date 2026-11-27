targetScope = 'resourceGroup'

param location string = 'centralus'
param vnetName string = 'vnet-bicep-bastion'
param vmName string = 'vm-bicep-kv-bastion'
param bastionName string = 'bastion-bicep-lab'
param vmSize string = 'Standard_B2s'
param adminUsername string

@secure()
param adminPassword string

@description('Name of the already existing Key Vault. This template does not create or modify the vault.')
param keyVaultName string

@description('Secret name populated by generator.sh. The VM identity reads this secret after permission is granted.')
param secretName string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.20.0.0/16']
    }
    subnets: [
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: '10.20.1.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.20.255.0/26'
        }
      }
    ]
  }
}

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-bicep-private-vm'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion-Subnet'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.20.255.0/26'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    networkSecurityGroup: {
      id: vmNsg.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-vm')
          }
        }
      }
    ]
  }
  dependsOn: [vnet]
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${bastionName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureBastionSubnet')
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
  dependsOn: [vnet]
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      }
      customData: base64(loadTextContent('cloud-init.yaml'))
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

output vmName string = vm.name
output vmPrincipalId string = vm.identity.principalId
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output bastionName string = bastion.name
output keyVaultName string = keyVaultName
output secretName string = secretName
