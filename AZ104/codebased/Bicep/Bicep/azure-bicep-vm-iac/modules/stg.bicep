// =============================================================================
// Module: stg.bicep
// Creates a StorageV2 account + blob containers and grants the
// "Storage Blob Data Reader" role to the given principals (e.g. VM identity).
// =============================================================================

@description('Globally unique storage account name: 3-24 chars, lowercase letters and numbers only.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region.')
param location string

@description('Storage SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

@description('Blob containers to create.')
param containerNames array = []

@description('Principal (object) IDs that get "Storage Blob Data Reader" on this account.')
param blobReaderPrincipalIds array = []

@description('Tags applied to the storage account.')
param tags object = {}

// Built-in role: Storage Blob Data Reader
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource stg 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: stg
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for containerName in containerNames: {
    parent: blobService
    name: containerName
    properties: {
      publicAccess: 'None'
    }
  }
]

resource blobReaderAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in blobReaderPrincipalIds: {
    name: guid(stg.id, principalId, storageBlobDataReaderRoleId)
    scope: stg
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal' // managed identities are service principals
    }
  }
]

@description('Resource ID of the storage account.')
output storageAccountId string = stg.id

@description('Name of the storage account.')
output storageAccountName string = stg.name

@description('Primary blob endpoint.')
output blobEndpoint string = stg.properties.primaryEndpoints.blob
