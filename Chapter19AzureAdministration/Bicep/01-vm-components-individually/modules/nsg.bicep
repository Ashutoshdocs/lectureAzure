param location string
param nsgName string
param adminSourceAddressPrefix string

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Admin-IP'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: adminSourceAddressPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

output nsgId string = nsg.id
