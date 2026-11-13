// Azure Service Health teaching demo
// Deploys: action group + Service Health alert (subscription scope) + Resource Health alert (resource group scope)
// Deploy at resource-group scope:
//   az deployment group create -g <rg> -f main.bicep -p alertEmail=you@example.com

@description('Email address that receives alert notifications')
param alertEmail string

@description('Region display names the Service Health alert should watch, e.g. ["Central India","Global"]')
param regions array = [
  'Central India'
  'South India'
  'Global'
]

@description('Name prefix for demo resources')
param prefix string = 'servicehealth-demo'

var subscriptionScope = subscription().id

// ---------- Action group ----------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}'
  location: 'Global'
  properties: {
    groupShortName: 'svchealth' // max 12 characters
    enabled: true
    emailReceivers: [
      {
        name: 'demo-email'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ---------- Service Health alert ----------
// Fires for incidents, maintenance, advisories and security events in the chosen regions.
resource serviceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-servicehealth-${prefix}'
  location: 'Global'
  properties: {
    enabled: true
    description: 'Demo: notify on Azure Service Health events affecting the selected regions.'
    scopes: [
      subscriptionScope
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          anyOf: [
            { field: 'properties.incidentType', equals: 'Incident' }
            { field: 'properties.incidentType', equals: 'Maintenance' }
            { field: 'properties.incidentType', equals: 'Informational' }
            { field: 'properties.incidentType', equals: 'ActionRequired' }
            { field: 'properties.incidentType', equals: 'Security' }
          ]
        }
        {
          field: 'properties.impactedServices[*].ImpactedRegions[*].RegionName'
          containsAny: regions
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// ---------- Resource Health alert ----------
// Fires when any resource in this resource group becomes Degraded or Unavailable,
// whether Azure caused it (PlatformInitiated) or a user did (UserInitiated).
resource resourceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-resourcehealth-${prefix}'
  location: 'Global'
  properties: {
    enabled: true
    description: 'Demo: notify when a resource in the demo resource group becomes Degraded or Unavailable.'
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          anyOf: [
            { field: 'properties.currentHealthStatus', equals: 'Degraded' }
            { field: 'properties.currentHealthStatus', equals: 'Unavailable' }
          ]
        }
        {
          anyOf: [
            { field: 'properties.cause', equals: 'PlatformInitiated' }
            { field: 'properties.cause', equals: 'UserInitiated' }
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

output actionGroupId string = actionGroup.id
output serviceHealthAlertId string = serviceHealthAlert.id
output resourceHealthAlertId string = resourceHealthAlert.id
