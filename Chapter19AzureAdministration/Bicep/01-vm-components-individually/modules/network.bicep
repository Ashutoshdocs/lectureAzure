param location string
param vnetName string
param addressPrefix string
param subnetName string
param subnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
        }
      }
    ]
  }
}

output subnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
output vnetId string = vnet.id
