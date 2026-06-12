using './main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'
param sku = 'Standard_LRS'
param enableHierarchicalNamespace = false
param enablePrivateEndpoints = false
param privateEndpointSubnetId = ''
