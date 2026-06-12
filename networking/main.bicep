@description('Base name')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('VNet address space (CIDR)')
param vnetAddressPrefix string = '10.0.0.0/16'

// --- Subnet address prefixes ---
param appServiceSubnetPrefix string = '10.0.1.0/24'         // App Service vnet integration
param privateEndpointSubnetPrefix string = '10.0.2.0/24'    // Private endpoints
param aciSubnetPrefix string = '10.0.3.0/24'                // ACI (deploymentScripts)
param functionSubnetPrefix string = '10.0.4.0/24'           // Function App vnet integration
param apimSubnetPrefix string = '10.0.5.0/24'               // API Management (internal mode)
param bastionSubnetPrefix string = '10.0.254.0/27'          // Azure Bastion (reserved name)

var vnetName = '${name}-vnet-${environment}'

// --- Virtual Network ---
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'app-service'
        properties: {
          addressPrefix: appServiceSubnetPrefix
          delegations: [
            {
              name: 'appServiceDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'aci-deployment'
        properties: {
          addressPrefix: aciSubnetPrefix
          delegations: [
            {
              name: 'aciDelegation'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'functions'
        properties: {
          addressPrefix: functionSubnetPrefix
          delegations: [
            {
              name: 'functionDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          delegations: [
            {
              name: 'apimDelegation'
              properties: {
                serviceName: 'Microsoft.ApiManagement/service'
              }
            }
          ]
        }
      }
      {
        name: 'AzureBastionSubnet'                    // MUST be named exactly this
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
  tags: {
    environment: environment
    managedBy: 'bicep'
  }
}

// --- Private DNS Zones (required for private endpoints) ---
var privateDnsZones = [
  { name: 'privatelink.database.windows.net',    service: 'SQL Server' }
  { name: 'privatelink.azurewebsites.net',       service: 'App Service' }
  { name: 'privatelink.blob.core.windows.net',   service: 'Blob Storage' }
  { name: 'privatelink.table.core.windows.net',  service: 'Table Storage' }
  { name: 'privatelink.queue.core.windows.net',  service: 'Queue Storage' }
  { name: 'privatelink.file.core.windows.net',   service: 'File Storage' }
  { name: 'privatelink.servicebus.windows.net',  service: 'Service Bus' }
  { name: 'privatelink.documents.azure.com',     service: 'Cosmos DB' }
  { name: 'privatelink.azure-api.net',           service: 'API Management' }
  { name: 'privatelink.eventgrid.azure.net',     service: 'Event Grid' }
]

resource privateDnsZonesResource 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in privateDnsZones: {
  name: zone.name
  location: 'global'
  properties: {}
  tags: {
    environment: environment
    service: zone.service
  }
}]

// --- Link DNS zones to VNet (so VNet-injected resources resolve private IPs) ---
resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zone, i) in privateDnsZones: {
  parent: privateDnsZonesResource[i]
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

// --- Outputs ---
output vnetName string = vnet.name
output vnetId string = vnet.id
output appServiceSubnetId string = '${vnet.id}/subnets/app-service'
output privateEndpointSubnetId string = '${vnet.id}/subnets/private-endpoints'
output aciSubnetId string = '${vnet.id}/subnets/aci-deployment'
output functionSubnetId string = '${vnet.id}/subnets/functions'
output apimSubnetId string = '${vnet.id}/subnets/apim'
output bastionSubnetId string = '${vnet.id}/subnets/AzureBastionSubnet'
output sqlDnsZoneId string = privateDnsZonesResource[0].id
output blobDnsZoneId string = privateDnsZonesResource[2].id
output serviceBusDnsZoneId string = privateDnsZonesResource[6].id
output cosmosDnsZoneId string = privateDnsZonesResource[7].id
