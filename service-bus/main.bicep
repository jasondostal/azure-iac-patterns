@description('Namespace name (globally unique — uses random suffix if not provided)')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('SKU: Basic | Standard | Premium')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Standard'

@description('Whether to enable private endpoints (Premium only)')
param enablePrivateEndpoints bool = false

@description('Private endpoint subnet ID (required for Premium + private endpoints)')
param privateEndpointSubnetId string = ''

var namespaceName = '${name}-sb-${environment}'

// --- Namespace ---
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    minimumTlsVersion: '1.2'
  }
  tags: {
    environment: environment
    managedBy: 'bicep'
  }
}

// --- Queues (examples) ---

resource commandQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'commands'
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'           // 14 days
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
  }
}

resource eventQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'events'
  properties: {
    maxSizeInMegabytes: 5120
    defaultMessageTimeToLive: 'P1D'
    lockDuration: 'PT5M'
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
    requiresSession: true                    // Ordered processing
  }
}

resource deadLetterQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'dead-letter'
  properties: {
    maxSizeInMegabytes: 5120
    defaultMessageTimeToLive: 'P90D'
    lockDuration: 'PT1M'
    maxDeliveryCount: 1
    deadLetteringOnMessageExpiration: false
  }
}

// --- Topics (pub/sub) ---

resource domainEventsTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'domain-events'
  properties: {
    maxSizeInMegabytes: 5120
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
  }
}

// Subscriptions on the topic — one per consumer
resource memberServiceSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: domainEventsTopic
  name: 'member-service'
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'P7D'
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: true
  }
}

resource notificationSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: domainEventsTopic
  name: 'notification-service'
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 5
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
  }
}

// --- Authorization Rule (listen-only for app consumers) ---
resource listenRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'app-listen'
  properties: {
    rights: ['Listen']
  }
}

resource sendRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'app-send'
  properties: {
    rights: ['Send']
  }
}

resource manageRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: ['Listen', 'Manage', 'Send']
  }
}

// --- Outputs ---
output namespaceName string = serviceBusNamespace.name
output namespaceEndpoint string = serviceBusNamespace.properties.serviceBusEndpoint
output commandsQueueName string = commandQueue.name
output eventsQueueName string = eventQueue.name
output domainEventsTopicName string = domainEventsTopic.name
