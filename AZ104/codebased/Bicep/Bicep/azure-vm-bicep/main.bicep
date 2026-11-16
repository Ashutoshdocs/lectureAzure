@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the virtual machine.')
param vmName string = 'demo-vm'

@description('Name of the virtual network.')
param vnetName string = '${vmName}-vnet'

@description('Name of the subnet.')
param subnetName string = 'default'

@description('Virtual network address space.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix.')
param subnetAddressPrefix string = '10.0.0.0/24'

@description('Name of the Network Security Group.')
param nsgName string = '${vmName}-nsg'

@description('Name of the public IP address.')
param publicIpName string = '${vmName}-pip'

@description('Name of the network interface.')
param nicName string = '${vmName}-nic'

@description('VM size.')
param vmSize string = 'Standard_B2s'

@description('Linux administrator username.')
@minLength(1)
param adminUsername string = 'azureadmin'

@description('SSH public key for the Linux administrator.')
param adminSshPublicKey string

@description('Ubuntu Marketplace image publisher.')
param imagePublisher string = 'Canonical'

@description('Ubuntu Marketplace image offer.')
param imageOffer string = 'ubuntu-24_04-lts'

@description('Ubuntu Marketplace image SKU.')
param imageSku string = 'server'

@description('Ubuntu Marketplace image version.')
param imageVersion string = 'latest'

@description('NSG rule priority for SSH.')
param sshRulePriority int = 1000

@description('SSH source IP/CIDR. Use your public IP/CIDR instead of * for better security.')
param sshSourceAddressPrefix string = '*'

@description('Whether to create a public IP for the VM.')
param createPublicIp bool = true

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: sshRulePriority
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: sshSourceAddressPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (createPublicIp) {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
          }
          publicIPAddress: createPublicIp ? {
            id: publicIp.id
          } : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
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
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
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
output vmId string = vm.id
output vnetName string = vnet.name
output nicName string = nic.name
output publicIpAddress string = createPublicIp ? publicIp.properties.ipAddress : 'No public IP created'
output sshCommand string = createPublicIp
  ? 'ssh ${adminUsername}@${publicIp.properties.ipAddress}'
  : 'No public IP. Use Azure Bastion or a private connection.'
