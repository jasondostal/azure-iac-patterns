using './main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'
param appServicePlanId = ''     // Fill in: App Service Plan resource ID
param storageAccountName = ''   // Fill in: Storage account name (lowercase)
param isLinux = true
param enableVnetIntegration = false
param vnetSubnetId = ''
