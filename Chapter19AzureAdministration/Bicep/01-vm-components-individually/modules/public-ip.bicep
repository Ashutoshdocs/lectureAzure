param location string
param publicIpName string

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
