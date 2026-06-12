@description('Base name')
param name string

@description('Azure region')
param location string

@description('Environment name')
param environment string

@description('SKU: Consumption | Developer | Basic | Standard | Premium')
@allowed(['Consumption', 'Developer', 'Basic', 'Standard', 'Premium'])
param sku string = 'Developer'     // Developer = free tier for dev/test

@description('Publisher email (required)')
param publisherEmail string = 'admin@contoso.com'

@description('Publisher name')
param publisherName string = 'Contoso API'

@description('Whether to enable VNet integration')
param enableVnetIntegration bool = false

@description('VNet subnet ID for internal mode (Premium only)')
param vnetSubnetId string = ''

var apimName = '${name}-apim-${environment}'

resource apiManagement 'Microsoft.ApiManagement/service@2023-12-01' = {
  name: apimName
  location: location
  sku: {
    name: sku
    capacity: (sku == 'Consumption' ? 0 : 1)
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: (enableVnetIntegration ? 'Internal' : 'None')
    virtualNetworkConfiguration: enableVnetIntegration && !empty(vnetSubnetId) ? {
      subnetResourceId: vnetSubnetId
    } : null
    publicNetworkAccess: enableVnetIntegration ? 'Disabled' : 'Enabled'
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
  }
  tags: {
    environment: environment
  }
}

// --- API Definition ---
resource contosoApi 'Microsoft.ApiManagement/service/apis@2023-12-01' = {
  parent: apiManagement
  name: 'contoso-api'
  properties: {
    displayName: 'Contoso API'
    path: 'contoso'
    serviceUrl: ''         // Fill in: backend URL (e.g., App Service URL)
    protocols: ['https']
    subscriptionRequired: true
    apiType: 'http'
  }
}

// --- Products (subscription tiers) ---
resource internalProduct 'Microsoft.ApiManagement/service/products@2023-12-01' = {
  parent: apiManagement
  name: 'internal'
  properties: {
    displayName: 'Internal'
    description: 'Internal consumers — no approval required'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource partnerProduct 'Microsoft.ApiManagement/service/products@2023-12-01' = {
  parent: apiManagement
  name: 'partner'
  properties: {
    displayName: 'Partners'
    description: 'External partners — approval required'
    subscriptionRequired: true
    approvalRequired: true
    state: 'published'
  }
}

// --- Named Values (Key Vault references for secrets) ---
resource keyVaultRef 'Microsoft.ApiManagement/service/namedValues@2023-12-01' = {
  parent: apiManagement
  name: 'keyvault-connection'
  properties: {
    displayName: 'Key Vault Connection'
    secret: true
    keyVault: {
      secretIdentifier: ''     // Fill in: Key Vault secret URI, e.g. https://contoso-kv-dev.vault.azure.net/secrets/sql-conn/
    }
  }
}

// --- Policies (global) ---
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-12-01' = {
  parent: apiManagement
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-header name="X-Environment" exists-action="override">
      <value>${environment}</value>
    </set-header>
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>https://${environment == 'prod' ? 'app' : '${environment}'}.contoso.com</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
    <rate-limit calls="100" renewal-period="60" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// --- Outputs ---
output apimName string = apiManagement.name
output gatewayUrl string = apiManagement.properties.gatewayUrl
output portalUrl string = apiManagement.properties.portalUrl
output apiName string = contosoApi.name
