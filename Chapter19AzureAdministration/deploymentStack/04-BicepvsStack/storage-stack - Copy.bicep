
targetScope = 'resourceGroup'

@description('Name for the first storage account. Must be globally unique.')
param storageAccountName1 string

@description('Name for the second storage account. Must be globally unique.')
param storageAccountName2 string

@description('Azure region for both storage accounts.')
param location string = resourceGroup().location

// STORAGE ACCOUNT 1
resource storageAccount1 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName1
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// BLOB SERVICE 1
resource blobService1 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount1
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// CONTAINER 1
resource container1 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService1
  name: 'container-one'
  properties: {
    publicAccess: 'None'
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
  }
}

// STORAGE ACCOUNT 2
resource storageAccount2 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName2
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// BLOB SERVICE 2
resource blobService2 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount2
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// CONTAINER 2
resource container2 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService2
  name: 'container-two'
  properties: {
    publicAccess: 'None'
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
  }
}

output storageAccount1Id string = storageAccount1.id
output storageAccount2Id string = storageAccount2.id
