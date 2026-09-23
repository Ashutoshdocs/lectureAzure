@description('Existing VM name.')
param vmName string

@description('Existing VM resource group.')
param vmResourceGroup string

@description('Existing Key Vault name.')
param keyVaultName string

@description('Secret name where the generated VM password will be stored.')
param secretName string = '${vmName}-admin-password'

@description('Existing VM administrator username.')
param adminUsername string

@description('VM operating system. Use Windows or Linux.')
@allowed([
  'Windows'
  'Linux'
])
param osType string

@description('Password generated outside Bicep and supplied securely at deployment time.')
@secure()
param generatedPassword string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
  scope: resourceGroup(vmResourceGroup)
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource vmPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  name: secretName
  parent: keyVault
  properties: {
    value: generatedPassword
  }
}

// This Run Command changes the existing local VM account password.
// The password is supplied as a secure deployment parameter and is not
// written as a normal Bicep output.
resource resetPassword 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  name: 'reset-admin-password'
  parent: vm
  location: vm.location
  properties: {
    source: {
      script: osType == 'Windows'
        ? 'net user "${adminUsername}" "${generatedPassword}"'
        : '#!/bin/bash\nprintf "%s:%s\\n" "${adminUsername}" "${generatedPassword}" | chpasswd'
    }
  }
  dependsOn: [
    vmPasswordSecret
  ]
}

output secretName string = secretName
output message string = 'VM password was reset and stored in Key Vault.'
