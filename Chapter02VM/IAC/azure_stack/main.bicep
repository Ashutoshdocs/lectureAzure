param location string = resourceGroup().location

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'stack-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'web-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'stack-nsg'
  location: location
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stackstorage12345'
  location: location
 tags: {
    environment: 'dev'
    owner: 'admin01'
  }

  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}
