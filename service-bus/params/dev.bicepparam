using './main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'
param sku = 'Standard'
param enablePrivateEndpoints = false
param privateEndpointSubnetId = ''
