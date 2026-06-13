targetScope = 'subscription'

// ═══════════════════════════════════════════════════════════════════════════
// azure-iac-patterns — foundry/main.bicep
//
// Standalone pattern demonstrating Azure AI Foundry infrastructure for
// agentic workloads:
//   1. Foundry Hub + AI Services account (Cognitive Services)
//   2. Model deployments (GPT-5-mini, text-embedding-3-small)
//   3. AI Search (for RAG vector stores at scale)
//   4. Foundry Project (agent scope)
//   5. Key Vault (secrets for AI Services keys)
//   6. App Service (hosts agent app, auth via managed identity)
//
// POST-DEPLOYMENT: After infrastructure is provisioned, run the agent setup
//   scripts from the app repo to create agents, vector stores, and voice
//   configuration. These are API-only resources that Bicep cannot create.
//
//   npm run setup-agents          → creates text agents + KB vector store
//   python provision_voice_agent.py → creates VoiceLive-enabled v2 agent
//
//   The App Service's managed identity is granted Azure AI Developer on
//   the AI Services account so the app can call Foundry data-plane APIs
//   without API keys.
// ═══════════════════════════════════════════════════════════════════════════

@description('Base name for all resources')
param name string = 'contoso'

@description('Azure region')
param location string = 'eastus'

@description('Environment name: dev, qa, stage, prod')
@allowed(['dev', 'qa', 'stage', 'prod'])
param environment string = 'dev'

// ── Resource Group ──────────────────────────────────────────────────────────

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${name}-ai-${environment}'
  location: location
  tags: {
    environment: environment
    app: name
    purpose: 'ai-agents'
  }
}

// ── AI Search (RAG vector store at scale) ───────────────────────────────────

module aiSearch './modules/ai-search.bicep' = {
  name: '${name}-search-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-search-${environment}'
    location: location
    sku: (environment == 'prod' ? 'standard' : 'basic')
    enableSemanticSearch: (environment == 'prod')
    replicaCount: (environment == 'prod' ? 3 : 1)
    environment: environment
  }
}

// ── Foundry Hub + AI Services + Models ──────────────────────────────────────

var modelDeployments = [
  // Chat completion models
  { name: 'gpt-5-mini', modelFormat: 'OpenAI', modelName: 'gpt-5-mini', modelVersion: '2024-10-21', skuName: 'GlobalStandard', skuCapacity: 10 }
  { name: 'gpt-4o', modelFormat: 'OpenAI', modelName: 'gpt-4o', modelVersion: '2024-08-06', skuName: 'GlobalStandard', skuCapacity: 10 }
  // Embedding models (vector search / RAG)
  { name: 'text-embedding-3-small', modelFormat: 'OpenAI', modelName: 'text-embedding-3-small', modelVersion: '1', skuName: 'GlobalStandard', skuCapacity: 10 }
  { name: 'text-embedding-3-large', modelFormat: 'OpenAI', modelName: 'text-embedding-3-large', modelVersion: '1', skuName: 'GlobalStandard', skuCapacity: 10 }
]

module foundryHub './modules/foundry-hub.bicep' = {
  name: '${name}-foundry-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-foundry-${environment}'
    location: location
    modelDeployments: modelDeployments
    environment: environment
  }
}

// ── Foundry Project ─────────────────────────────────────────────────────────

module foundryProject './modules/foundry-project.bicep' = {
  name: '${name}-proj-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-proj-${environment}'
    location: location
    hubId: foundryHub.outputs.hubId
    aiServicesId: foundryHub.outputs.aiServicesId
    aiSearchServiceId: aiSearch.outputs.searchServiceId
    environment: environment
  }
}

// ── Key Vault (secrets for storage keys + optional API key fallback) ────────

module keyVault './modules/key-vault.bicep' = {
  name: '${name}-ai-kv-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-ai-kv-${environment}'
    location: location
    tenantId: subscription().tenantId
    environment: environment
  }
}

// ── App Service Plan + App Service (hosts the agent front-end) ──────────────

module appServicePlan './modules/app-service-plan.bicep' = {
  name: '${name}-ai-asp-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-ai-asp-${environment}'
    location: location
    skuName: (environment == 'prod' ? 'S1' : 'B1')
    skuTier: (environment == 'prod' ? 'Standard' : 'Basic')
    environment: environment
    osKind: 'linux'
  }
}

module appService './modules/app-service.bicep' = {
  name: '${name}-ai-app-${environment}'
  scope: resourceGroup
  params: {
    name: '${name}-ai-app-${environment}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    runtimeStack: 'NODE|22-lts'
    alwaysOn: (environment == 'prod')
    environment: environment
    enableManagedIdentity: true
    appSettings: {
      PROJECT_ENDPOINT: foundryProject.outputs.projectEndpoint
      MODEL_DEPLOYMENT: 'gpt-5-mini'
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

output foundryEndpoint string = foundryHub.outputs.aiServicesEndpoint
output projectEndpoint string = foundryProject.outputs.projectEndpoint
output aiSearchEndpoint string = aiSearch.outputs.searchEndpoint
output appServiceUrl string = appService.outputs.defaultHostName
output appServiceIdentityPrincipalId string = appService.outputs.managedIdentityPrincipalId
output keyVaultName string = keyVault.outputs.name

// ── Post-deployment steps (run after infra is provisioned) ──────────────────
//
// 1. Grant App Service managed identity access to AI Services:
//    az role assignment create \\
//      --assignee ${appServiceIdentityPrincipalId} \\
//      --role "Azure AI Developer" \\
//      --scope ${foundryHub.outputs.aiServicesId}
//
// 2. Run agent setup scripts from app repo (npm run setup-agents, etc.)
//
// 3. The app reads PROJECT_ENDPOINT + MODEL_DEPLOYMENT from App Settings;
//    agent IDs come from .env written by setup scripts (or App Configuration)
