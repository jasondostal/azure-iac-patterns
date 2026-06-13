targetScope = 'subscription'

// ═══════════════════════════════════════════════════════════════════════════
// azure-iac-patterns — identity/main.bicep
//
// Standalone identity pattern demonstrating:
//   1. Entra ID App Registration (config contract — create externally via CLI)
//   2. Azure AD B2C configuration (for external partner/customer identities)
//   3. APIM API with multi-auth wired (internal + B2C + client credentials)
//   4. Key Vault for storing secrets referenced by APIM
//
// PRE-REQUISITE: App registrations must be created BEFORE deploying this
// Bicep. Because Bicep cannot create Entra app registrations directly
// (no Microsoft.Graph provider), create them via Azure CLI:
//
//   az ad app create --display-name "contoso-api-internal-dev" \
//     --sign-in-audience AzureADMyOrg \
//     --identifier-uris "api://contoso-api-internal-dev"
//
// Then pass the resulting client IDs as parameters below.
//
// USE CASES:
//   Internal: Employee navigates to https://apim.contoso.com/members/v1/member
//             → APIM validate-jwt against corporate Entra ID → App Service
//   External: Partner bank backend calls /members/v1/member with client_credentials
//             → APIM validate-jwt against client-credential app registration → App Service
//   External: Partner employee logs in via B2C sign-in policy
//             → APIM validate-jwt against B2C tenant → App Service
// ═══════════════════════════════════════════════════════════════════════════

@description('Base name for all resources')
param name string = 'contoso'

@description('Azure region')
param location string = 'eastus'

@description('Environment name: dev, qa, stage, prod')
@allowed(['dev', 'qa', 'stage', 'prod'])
param environment string = 'dev'

@description('Entra tenant ID (corporate directory)')
param tenantId string

@description('Internal employee API app registration client ID (create externally first)')
param internalApiClientId string

@description('M2M client credential app registration client ID (create externally first)')
param m2mClientId string = ''

// ── Resource Group (create first — needed as scope for all modules) ────────

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${name}-${environment}'
  location: location
}

// ── Entra ID App Registration Config Contracts ──────────────────────────────

// Internal employee API — config contract (app reg created via CLI)
module internalApiApp '../../azure-platform-iac/modules/identity/entra-app-registration.bicep' = {
  name: '${name}-api-internal-${environment}'
  scope: resourceGroup
  params: {
    tenantId: tenantId
    clientId: internalApiClientId
    displayName: '${name}-api-internal-${environment}'
    exposeApi: true
    scopes: [
      { adminConsentDisplayName: 'Read members', adminConsentDescription: 'Allows reading member data', value: 'Members.Read', type: 'User', isEnabled: true }
      { adminConsentDisplayName: 'Write members', adminConsentDescription: 'Allows creating and updating members', value: 'Members.Write', type: 'User', isEnabled: true }
    ]
    appRoles: [
      { id: '00000000-0000-0000-0000-000000000001', allowedMemberTypes: ['User'], description: 'Can read member data', displayName: 'Member Reader', value: 'Members.Reader' }
      { id: '00000000-0000-0000-0000-000000000002', allowedMemberTypes: ['User'], description: 'Can read and write member data', displayName: 'Member Writer', value: 'Members.Writer' }
    ]
    environment: environment
  }
}

// M2M client credential app — config contract (app reg created via CLI)
module m2mApp '../../azure-platform-iac/modules/identity/entra-app-registration.bicep' = if (!empty(m2mClientId)) {
  name: '${name}-api-m2m-${environment}'
  scope: resourceGroup
  params: {
    tenantId: tenantId
    clientId: m2mClientId
    displayName: '${name}-api-m2m-${environment}'
    exposeApi: false
    appRoles: [
      { id: '00000000-0000-0000-0000-000000000003', allowedMemberTypes: ['Application'], description: 'Machine-to-machine access to members API', displayName: 'API Caller', value: 'API.Caller' }
    ]
    environment: environment
  }
}

// ── B2C Configuration (external partner/customer identities) ────────────────

module b2cConfig '../../azure-platform-iac/modules/identity/entra-b2c.bicep' = {
  name: '${name}-b2c-config-${environment}'
  scope: resourceGroup
  params: {
    tenantName: '${name}b2c'     // replace with your actual B2C tenant name
    tenantId: ''                  // B2C tenant GUID — fill in after creation
    apiClientId: ''               // B2C app registration client ID — fill in
    userFlows: [
      { name: 'B2C_1_signin', displayName: 'Sign in' }
      { name: 'B2C_1_signup', displayName: 'Sign up' }
      { name: 'B2C_1_reset', displayName: 'Password reset' }
    ]
    environment: environment
  }
}

// ── Key Vault (secrets for APIM named values) ───────────────────────────────

module keyVault '../../azure-platform-iac/modules/security/key-vault.bicep' = {
  name: '${name}-kv-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-kv-${environment}'
    location: location
    tenantId: tenantId
    environment: environment
  }
}

// ── API Management ──────────────────────────────────────────────────────────

module apim '../../azure-platform-iac/modules/integration/api-management.bicep' = {
  name: '${name}-apim-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-apim-${environment}'
    location: location
    sku: (environment == 'prod' ? 'Standard' : 'Developer')
    publisherEmail: 'admin@contoso.com'
    publisherName: 'Contoso API'
    environment: environment
  }
}

// Members API with multi-auth
module membersApi '../../azure-platform-iac/modules/integration/apim-api.bicep' = {
  name: '${name}-api-members-${environment}'
  scope: resourceGroup
  params: {
    apimServiceName: apim.outputs.name
    apiName: 'contoso-members-api'
    displayName: 'Contoso Members API'
    path: 'members'
    serviceUrl: 'https://${name}-app-${environment}.azurewebsites.net'
    apiVersion: 'v1'
    subscriptionRequired: true
    environment: environment

    // Auth: internal employees (Entra ID)
    enableEntraAuth: true
    entraTenantId: tenantId
    entraAudience: internalApiApp.outputs.applicationId

    // Auth: external B2C users
    enableB2CAuth: false     // set true after B2C tenant is provisioned
    b2cTenantName: b2cConfig.outputs.tenantName
    b2cSignInPolicy: b2cConfig.outputs.defaultSignInPolicy
    b2cAudience: b2cConfig.outputs.apiClientId

    // Auth: M2M client credentials
    enableClientCredentialAuth: !empty(m2mClientId)
    clientCredentialTenantId: tenantId
    clientCredentialAudience: m2mClientId

    createProducts: true
    corsOrigins: ['https://${environment}.contoso.com']
    rateLimitCalls: (environment == 'prod' ? 1000 : 100)
    rateLimitPeriod: 60
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

output apimGatewayUrl string = apim.outputs.gatewayUrl
output membersApiPath string = '/members/v1'
output internalApiAudience string = internalApiApp.outputs.audience
output internalApiIdentifierUri string = internalApiApp.outputs.identifierUris[0]
output m2mClientAppId string = !empty(m2mClientId) ? m2mClientId : ''
output keyVaultName string = keyVault.outputs.name
