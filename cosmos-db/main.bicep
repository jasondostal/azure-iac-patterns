@description('Base name')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('Whether to enable serverless (pay-per-request) mode')
param enableServerless bool = true

@description('Whether to enable private endpoints')
param enablePrivateEndpoints bool = false

@description('Private endpoint subnet ID')
param privateEndpointSubnetId string = ''

@description('Whether to enable multi-region writes (prod only)')
param enableMultiRegionWrite bool = false

@description('Backup region for multi-region failover')
param backupRegion string = ''

var accountName = '${name}-cosmos-${environment}'

// --- Cosmos DB Account ---
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    capabilities: [
      { name: 'EnableServerless' }
    ]
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    enableFreeTier: (environment == 'dev')
    enableAutomaticFailover: enableMultiRegionWrite
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'    // Strong enough for CU, cheaper than Strong
    }
    backupPolicy: environment == 'prod' ? {
      type: 'Continuous'
      continuousModeProperties: {
        tier: 'Continuous30Days'
      }
    } : {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
      }
    }
    databaseAccountOfferType: (enableServerless ? null : 'Standard')
  }
  tags: {
    environment: environment
    managedBy: 'bicep'
  }
}

// --- Databases ---

// Members DB — partitioned by member ID
resource memberDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'MembersDb'
  properties: {
    resource: {
      id: 'MembersDb'
    }
  }
}

// Events DB — time-series event sourcing
resource eventsDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'EventsDb'
  properties: {
    resource: {
      id: 'EventsDb'
    }
  }
}

// --- Containers (tables in SQL API) ---

resource memberContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: memberDb
  name: 'members'
  properties: {
    resource: {
      id: 'members'
      partitionKey: {
        paths: ['/memberId']
        kind: 'Hash'
      }
      defaultTtl: -1                    // No TTL — permanent records
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          { path: '/*' }
        ]
        excludedPaths: [
          { path: '/"_etag"/?' }
        ]
        compositeIndexes: [
          [{ path: '/lastName', order: 'ascending' }, { path: '/firstName', order: 'ascending' }]
        ]
      }
    }
  }
}

resource memberAccountsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: memberDb
  name: 'accounts'
  properties: {
    resource: {
      id: 'accounts'
      partitionKey: {
        paths: ['/memberId']
        kind: 'Hash'
      }
      defaultTtl: -1
    }
  }
}

resource memberEventsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: eventsDb
  name: 'member-events'
  properties: {
    resource: {
      id: 'member-events'
      partitionKey: {
        paths: ['/aggregateId']         // Event sourcing: partition by aggregate
        kind: 'Hash'
      }
      defaultTtl: -1
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [{ path: '/eventType/?' }, { path: '/timestamp/?' }, { path: '/*' }]
      }
    }
  }
}

resource deadLetterContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: eventsDb
  name: 'dead-letter'
  properties: {
    resource: {
      id: 'dead-letter'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
      defaultTtl: 7776000                 // Auto-delete after 90 days
    }
  }
}

// --- Outputs ---
output accountName string = cosmosAccount.name
output endpoint string = cosmosAccount.properties.documentEndpoint
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
output memberDbName string = memberDb.name
output eventsDbName string = eventsDb.name
