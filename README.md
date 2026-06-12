# Azure IAC Patterns

Standalone Bicep reference modules for common Azure services. Each module is self-contained with its own parameter file — grab what you need, wire into your deployment.

## Related Repos

| Repo | Purpose |
|------|--------|
| [azure-platform-iac](../azure-platform-iac) | Platform modules (generic, reusable templates) |
| [azure-iac-reference](../azure-iac-reference) | Reference app consuming platform modules |
| **azure-iac-patterns** (this repo) | Standalone service patterns catalog |

## Modules

| Module | What | Key Features |
|--------|------|-------------|
| **service-bus** | Azure Service Bus namespace, queues, topics, subscriptions | Commands queue (14d TTL), Events queue (session-enabled), Dead-letter queue, Domain-events topic with per-service subscriptions, Auth rules (send/listen/manage) |
| **eventgrid** | Event Grid system topic + custom topic + subscriptions | CloudEvents v1.0, Service Bus destination, WebHook destination (Functions), Dead-letter to blob, Retry policy |
| **api-management** | API Management (APIM) with API, products, policies | Developer tier for dev, Internal + Partner products, Key Vault named values, Global policy (CORS, rate-limit, header strip), Internal VNet mode |
| **cosmos-db** | Cosmos DB account + databases + containers | Serverless mode (free in dev), Members + Events databases, Partitioned containers, Composite indexes, Change feed support, Continuous backup (prod), Free tier (dev) |
| **storage** | Storage account + blob containers + file shares + tables + queues | 5 blob containers (documents, uploads, archive, eventgrid-deadletter, logs), Soft-delete + versioning, CORS, File share (SMB), Table (audit log), Queue (notifications) |
| **functions** | Function App + 4 function triggers | HTTP trigger, Service Bus queue trigger, Blob trigger, Timer trigger (daily 6 AM), Cosmos DB change feed trigger, VNet integration, .NET 9 isolated |
| **networking** | VNet + 6 subnets + 10 private DNS zones | App Service, Private Endpoints, ACI deployment, Functions, API Management, Azure Bastion subnets. DNS zones for SQL, App Service, Blob, Table, Queue, File, Service Bus, Cosmos DB, API Management, Event Grid. Automatic VNet link. |

## Usage

Each module is a standalone Bicep deployment. Pick the ones you need:

```bash
# Deploy networking (first — everything else depends on its subnets)
az deployment group create \
  --resource-group rg-contoso-dev \
  --template-file networking/main.bicep \
  --parameters networking/params/dev.bicepparam

# Deploy a service
az deployment group create \
  --resource-group rg-contoso-dev \
  --template-file storage/main.bicep \
  --parameters storage/params/dev.bicepparam
```

## Convention

- All modules use `name`, `location`, `environment` parameters for consistency
- `enablePrivateEndpoints` toggle on everything — flip to `true` in QA+
- `params/dev.bicepparam` is a starting point — copy/modify for qa, stage, prod
- Outputs expose resource IDs for chaining in `main.bicep` orchestrations
- All resources tagged with `environment` and `managedBy: bicep`

## Wire-up Example

```bicep
// main.bicep — orchestrate multiple patterns
targetScope = 'resourceGroup'

param name string
param location string
param environment string

module net './networking/main.bicep' = {
  name: 'networking'
  params: { name: name; location: location; environment: environment }
}

module storage './storage/main.bicep' = {
  name: 'storage'
  params: {
    name: name; location: location; environment: environment
    enablePrivateEndpoints: true
    privateEndpointSubnetId: net.outputs.privateEndpointSubnetId
  }
}

module serviceBus './service-bus/main.bicep' = {
  name: 'servicebus'
  params: { name: name; location: location; environment: environment }
}
```

## Design Notes

- **Serverless-first** — Cosmos DB and Functions default to serverless/pay-per-request. Flip to provisioned in prod if steady-state traffic warrants.
- **Private endpoints** — every module has the toggle. Networking module provides all 10 private DNS zones and VNet links.
- **Idempotent** — modules use resource names derived from `{name}-{service}-{environment}`. Rerunning is safe.
- **No connection strings in output** — use managed identity + RBAC instead. The storage module outputs the account key only because Functions runtime requires `AzureWebJobsStorage` as a connection string (Azure limitation — not a design choice).
