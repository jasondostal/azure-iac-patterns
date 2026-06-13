@description('Base name')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('App Service Plan ID (Functions run on App Service Plans, not standalone)')
param appServicePlanId string

@description('Storage account name for Functions runtime')
param storageAccountName string

@description('Whether to deploy to a Linux plan')
param isLinux bool = true

@description('Whether to enable VNet integration')
param enableVnetIntegration bool = false

@description('VNet integration subnet ID')
param vnetSubnetId string = ''

var funcAppName = '${name}-func-${environment}'

// --- Function App ---
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|10.0'   // .NET 10 isolated process
      alwaysOn: (environment == 'prod')
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: enableVnetIntegration
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=core.windows.net;AccountKey=${listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2024-01-01').keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: {
    environment: environment
    managedBy: 'bicep'
  }
}

// VNet integration
resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2023-12-01' = if (enableVnetIntegration && !empty(vnetSubnetId)) {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: vnetSubnetId
    swiftSupported: true
  }
}

// --- Functions (example triggers) ---

// HTTP-triggered: process member update
resource memberUpdateFunction 'Microsoft.Web/sites/functions@2023-12-01' = {
  parent: functionApp
  name: 'ProcessMemberUpdate'
  properties: {
    config: {
      bindings: [
        {
          name: 'req'
          type: 'httpTrigger'
          direction: 'in'
          authLevel: 'function'
          methods: ['POST']
          route: 'members/{memberId}'
        }
        {
          name: 'res'
          type: 'http'
          direction: 'out'
        }
      ]
    }
  }
}

// Service Bus queue-triggered
resource commandProcessorFunction 'Microsoft.Web/sites/functions@2023-12-01' = {
  parent: functionApp
  name: 'ProcessCommand'
  properties: {
    config: {
      bindings: [
        {
          name: 'commandMessage'
          type: 'serviceBusTrigger'
          direction: 'in'
          queueName: 'commands'
          connection: 'ServiceBusConnection'
        }
      ]
    }
  }
}

// Blob-triggered: process uploaded files
resource fileProcessorFunction 'Microsoft.Web/sites/functions@2023-12-01' = {
  parent: functionApp
  name: 'ProcessUploadedFile'
  properties: {
    config: {
      bindings: [
        {
          name: 'blob'
          type: 'blobTrigger'
          direction: 'in'
          path: 'uploads/{name}'
          connection: 'AzureWebJobsStorage'
        }
      ]
    }
  }
}

// Timer-triggered: daily reconciliation
resource dailyReconciliationFunction 'Microsoft.Web/sites/functions@2023-12-01' = {
  parent: functionApp
  name: 'DailyReconciliation'
  properties: {
    config: {
      bindings: [
        {
          name: 'timer'
          type: 'timerTrigger'
          direction: 'in'
          schedule: '0 0 6 * * *'     // 6 AM UTC daily
        }
      ]
    }
  }
}

// Cosmos DB change feed trigger
resource memberChangeFeedFunction 'Microsoft.Web/sites/functions@2023-12-01' = {
  parent: functionApp
  name: 'MemberChangeFeed'
  properties: {
    config: {
      bindings: [
        {
          name: 'documents'
          type: 'cosmosDBTrigger'
          direction: 'in'
          databaseName: 'MembersDb'
          collectionName: 'members'
          connectionStringSetting: 'CosmosDbConnection'
          leaseCollectionName: 'leases'
          createLeaseCollectionIfNotExists: true
        }
      ]
    }
  }
}

// --- Outputs ---
output functionAppName string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output managedIdentityPrincipalId string = functionApp.identity.principalId
