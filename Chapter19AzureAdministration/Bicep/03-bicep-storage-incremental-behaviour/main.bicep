targetScope = 'resourceGroup'

@description('Globally unique name: 3-24 lowercase letters and numbers.')
@minLength(3)
@maxLength(24)
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

resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/images'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountId string = storage.id
output storageAccountName string = storage.name
