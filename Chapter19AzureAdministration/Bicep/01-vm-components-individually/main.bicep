targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'centralus'

@description('Linux administrator username.')
param adminUsername string = 'azureadmin'

@description('SSH public key contents. Never provide a private key.')
@secure()
param sshPublicKey string

@description('Restrict SSH to your public IP, for example 203.0.113.10/32.')
param adminSourceAddressPrefix string

param vmSize string = 'Standard_B2s'

module network './modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    vnetName: 'vnet-bicep-components'
    addressPrefix: '10.10.0.0/16'
    subnetName: 'snet-vm'
    subnetPrefix: '10.10.1.0/24'
  }
}

module nsg './modules/nsg.bicep' = {
  name: 'nsg-deployment'
  params: {
    location: location
    nsgName: 'nsg-bicep-components'
    adminSourceAddressPrefix: adminSourceAddressPrefix
  }
}

module publicIp './modules/public-ip.bicep' = {
  name: 'public-ip-deployment'
  params: {
    location: location
    publicIpName: 'pip-bicep-components'
  }
}

module nic './modules/nic.bicep' = {
  name: 'nic-deployment'
  params: {
    location: location
    nicName: 'nic-bicep-components'
    subnetId: network.outputs.subnetId
    nsgId: nsg.outputs.nsgId
    publicIpId: publicIp.outputs.publicIpId
  }
}

module vm './modules/vm.bicep' = {
  name: 'vm-deployment'
  params: {
    location: location
    vmName: 'vm-bicep-components'
    vmSize: vmSize
    nicId: nic.outputs.nicId
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
  }
}

output vmName string = vm.outputs.vmName
output vmPublicIp string = publicIp.outputs.publicIpAddress
output vmId string = vm.outputs.vmId
