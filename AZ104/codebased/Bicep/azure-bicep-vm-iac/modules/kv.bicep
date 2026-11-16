// =============================================================================
// Module: kv.bicep
// Works against a MANUALLY CREATED Key Vault (it never creates a vault).
//  - Looks up the existing vault and returns its ID / URI.
//  - Optionally grants "Key Vault Secrets User" to principals (e.g. the VM
//    managed identity) so the VM itself can read secrets at runtime.
//    Requires the vault to use Azure RBAC authorization.
//
// Deploy this module with scope = the Key Vault's resource group.
// NOTE: reading the admin password during deployment is done in
// mainresource.bicep with getSecret(), because getSecret() can only be called
// on an `existing` vault declared in the file that passes it to a module.
// =============================================================================

@description('Name of the existing (manually created) Key Vault.')
param keyVaultName string

@description('Principal IDs to grant "Key Vault Secrets User" on the vault. Leave empty to skip.')
param secretsUserPrincipalIds array = []

// Built-in role: Key Vault Secrets User
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secretsUserAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in secretsUserPrincipalIds: {
    name: guid(kv.id, principalId, keyVaultSecretsUserRoleId)
    scope: kv
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

@description('Resource ID of the Key Vault.')
output keyVaultId string = kv.id

@description('Vault URI, e.g. https://<name>.vault.azure.net/.')
output keyVaultUri string = kv.properties.vaultUri
