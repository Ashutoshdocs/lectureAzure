// =============================================================================
// mainresource.bicep  -  the actual execution / orchestration file
//
// Deployed at SUBSCRIPTION scope, once per environment (dev | psq | prod),
// using the parameter file in environments/<env>/<env>.parameters.json.
//
// Flow:
//   1. Resource group for the environment
//   2. NSG + VNet + subnet                      (modules/vnet.bicep)
//   3. VM with System-Assigned Managed Identity (modules/vm.bicep)
//        admin username + password are read from the MANUALLY created
//        Key Vault with getSecret()  (secrets created by passwordgenerator.sh)
//   4. Storage account + "Storage Blob Data Reader" for the VM identity
//                                               (modules/stg.bicep)
//   5. Key Vault module: looks up the vault, optionally grants the VM
//      "Key Vault Secrets User"                 (modules/kv.bicep)
// =============================================================================

targetScope = 'subscription'

// ---------------------------------------------------------------- general ---
@description('Subscription ID of this environment (also where the Key Vault lives). Set it in the parameter file.')
param subscriptionId string

@description('Environment name.')
@allowed([
  'dev'
  'psq'
  'prod'
])
param environment string

@description('Azure region for all resources.')
param location string

@description('Resource group that will hold the environment resources (created if missing).')
param resourceGroupName string

@description('Extra tags merged into every resource.')
param tags object = {}

// ---------------------------------------------------------------- network ---
param vnetName string
param vnetAddressPrefixes array
param subnetName string
param subnetAddressPrefix string
param nsgName string

// --------------------------------------------------------------------- vm ---
param vmName string
param vmSize string

@allowed([
  'Linux'
  'Windows'
])
param osType string = 'Linux'

param imageReference object
param osDiskType string = 'StandardSSD_LRS'
param osDiskSizeGB int = 64
param enablePublicIp bool = false
param availabilityZone string = ''

// ---------------------------------------------------------------- storage ---
param storageAccountName string
param storageSkuName string = 'Standard_LRS'
param storageContainerNames array = []

// -------------------------------------------- key vault (manually created) ---
@description('Name of the manually created Key Vault holding the VM credentials.')
param keyVaultName string

@description('Resource group of the Key Vault.')
param keyVaultResourceGroup string

@description('Secret name holding the VM admin username.')
param adminUsernameSecretName string

@description('Secret name holding the VM admin password.')
param adminPasswordSecretName string

@description('Also give the VM identity "Key Vault Secrets User" on the vault (vault must use RBAC).')
param grantVmKeyVaultSecretsUser bool = false

// ======================================================================= //

var commonTags = union(tags, {
  environment: environment
  deployedBy: 'bicep'
})

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

// Existing, manually created vault - used only to read the VM credentials.
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(subscriptionId, keyVaultResourceGroup)
}

module network '../modules/vnet.bicep' = {
  name: '${environment}-network'
  scope: rg
  params: {
    vnetName: vnetName
    location: location
    addressPrefixes: vnetAddressPrefixes
    subnetName: subnetName
    subnetAddressPrefix: subnetAddressPrefix
    nsgName: nsgName
    tags: commonTags
  }
}

module vm '../modules/vm.bicep' = {
  name: '${environment}-vm'
  scope: rg
  params: {
    vmName: vmName
    location: location
    vmSize: vmSize
    osType: osType
    imageReference: imageReference
    adminUsername: keyVault.getSecret(adminUsernameSecretName) // fetched from Key Vault
    adminPassword: keyVault.getSecret(adminPasswordSecretName) // fetched from Key Vault
    subnetId: network.outputs.subnetId
    osDiskType: osDiskType
    osDiskSizeGB: osDiskSizeGB
    enablePublicIp: enablePublicIp
    zone: availabilityZone
    tags: commonTags
  }
}

module storage '../modules/stg.bicep' = {
  name: '${environment}-storage'
  scope: rg
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: storageSkuName
    containerNames: storageContainerNames
    blobReaderPrincipalIds: [
      vm.outputs.principalId // VM managed identity -> Storage Blob Data Reader
    ]
    tags: commonTags
  }
}

module kv '../modules/kv.bicep' = {
  name: '${environment}-keyvault'
  scope: resourceGroup(subscriptionId, keyVaultResourceGroup)
  params: {
    keyVaultName: keyVaultName
    secretsUserPrincipalIds: grantVmKeyVaultSecretsUser ? [
      vm.outputs.principalId
    ] : []
  }
}

// ---------------------------------------------------------------- outputs ---
output resourceGroupName string = rg.name
output vmName string = vm.outputs.vmName
output vmPrincipalId string = vm.outputs.principalId
output vmPrivateIp string = vm.outputs.privateIpAddress
output storageAccountName string = storage.outputs.storageAccountName
output storageBlobEndpoint string = storage.outputs.blobEndpoint
output keyVaultUri string = kv.outputs.keyVaultUri
