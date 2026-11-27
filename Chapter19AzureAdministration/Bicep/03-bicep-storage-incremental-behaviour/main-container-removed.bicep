// Teaching variant: the images container declaration has been removed.
// In Incremental mode this does NOT delete an existing images container.
targetScope = 'resourceGroup'

param storageAccountName string
param location string = 'centralus'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource logsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/logs'
  properties: {
    publicAccess: 'None'
  }
}
