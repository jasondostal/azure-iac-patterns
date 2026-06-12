using './main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'
param sku = 'Developer'
param enableVnetIntegration = false
param vnetSubnetId = ''
