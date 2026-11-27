// Reset template: both containers are declared.
targetScope = 'resourceGroup'
@minLength(3)
@maxLength(24)
param storageAccountName string
param location string = 'centralus'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
resource logs 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/logs'
  properties: { publicAccess: 'None' }
}
resource images 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/images'
  properties: { publicAccess: 'None' }
}
