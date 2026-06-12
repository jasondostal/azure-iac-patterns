@description('Base name (globally unique — storage account names must be 3-24 lowercase alphanumeric)')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('SKU: Standard_LRS | Standard_GRS | Standard_RAGRS | Standard_ZRS | Premium_LRS')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS'])
param sku string = (environment == 'prod' ? 'Standard_GRS' : 'Standard_LRS')

@description('Whether to enable hierarchical namespace (Data Lake Gen2)')
param enableHierarchicalNamespace bool = false

@description('Whether to disable public access (private endpoints only)')
param enablePrivateEndpoints bool = false

@description('Delete retention in days (soft-delete for blobs) — 7 min')
param blobDeleteRetentionDays int = 7

@description('Container delete retention in days')
param containerDeleteRetentionDays int = 7

var storageName = toLower(take('${name}${environment}st', 24))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: sku
  }
  properties: {
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    isHnsEnabled: enableHierarchicalNamespace
    networkAcls: {
      defaultAction: enablePrivateEndpoints ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
    supportsHttpsTrafficOnly: true
  }
  tags: {
    environment: environment
    managedBy: 'bicep'
  }
}

// Blob service properties + containers
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: blobDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: containerDeleteRetentionDays
    }
    isVersioningEnabled: true
    cors: {
      corsRules: [
        {
          allowedOrigins: ['https://${name}-app-${environment}.azurewebsites.net']
          allowedMethods: ['GET', 'PUT', 'HEAD']
          allowedHeaders: ['*']
          exposedHeaders: ['x-ms-request-id']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// Blob containers
resource documents 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'documents'
  properties: { publicAccess: 'None' }
}

resource uploads 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'uploads'
  properties: { publicAccess: 'None' }
}

resource archives 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'archive'
  properties: { publicAccess: 'None' }
}

resource eventgridDeadletter 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'eventgrid-deadletter'
  properties: { publicAccess: 'None' }
}

resource logs 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'logs'
  properties: { publicAccess: 'None' }
}

// File share
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource appDataShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-04-01' = {
  parent: fileServices
  name: 'app-data'
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 100
    enabledProtocols: 'SMB'
  }
}

// Table
resource tableServices 'Microsoft.Storage/storageAccounts/tableServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource auditTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-04-01' = {
  parent: tableServices
  name: 'auditlog'
}

// Queue
resource queueServices 'Microsoft.Storage/storageAccounts/queueServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource notificationsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-04-01' = {
  parent: queueServices
  name: 'notifications'
}

// --- Outputs ---
output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table
output queueEndpoint string = storageAccount.properties.primaryEndpoints.queue
