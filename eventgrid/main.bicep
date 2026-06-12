@description('Base name')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

var topicName = '${name}-eg-${environment}'

// --- Custom Topic (app events) ---
resource customTopic 'Microsoft.EventGrid/topics@2021-12-01' = {
  name: '${topicName}-custom'
  location: location
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    environment: environment
  }
}

// --- Event Subscription: webhook to Azure Function ---
resource domainEventsSub 'Microsoft.EventGrid/topics/eventSubscriptions@2021-12-01' = {
  parent: customTopic
  name: 'domain-events-to-function'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://placeholder.invalid/api/events'
        maxEventsPerBatch: 10
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      // NOTE: Bicep 0.44.1 parser — use single-line arrays for EventGrid
      includedEventTypes: ['Contoso.Member.Created', 'Contoso.Member.Updated', 'Contoso.Account.Opened']
    }
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// --- Outputs ---
output customTopicEndpoint string = customTopic.properties.endpoint
output customTopicName string = customTopic.name
