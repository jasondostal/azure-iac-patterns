// Parameters for the identity pattern — dev environment
using 'main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'

// Corporate Entra tenant ID
param tenantId = ''     // Your tenant GUID
