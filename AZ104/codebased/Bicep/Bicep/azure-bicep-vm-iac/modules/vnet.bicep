// =============================================================================
// Module: vnet.bicep
// Creates an NSG and a VNet with one subnet (NSG attached) for the VM.
// =============================================================================

@description('Name of the virtual network.')
param vnetName string

@description('Azure region.')
param location string

@description('Address space(s) of the VNet, e.g. ["10.10.0.0/16"].')
param addressPrefixes array

@description('Name of the VM subnet.')
param subnetName string

@description('Address prefix of the VM subnet, e.g. 10.10.1.0/24.')
param subnetAddressPrefix string

@description('Name of the network security group attached to the subnet.')
param nsgName string

@description('Tags applied to every resource in this module.')
param tags object = {}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    // No inbound allow rules: default rules deny inbound from the Internet.
    // Add rules here (e.g. allow 22/3389 from your IP) only if you really need them.
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
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

@description('Resource ID of the VNet.')
output vnetId string = vnet.id

@description('Resource ID of the VM subnet.')
output subnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
