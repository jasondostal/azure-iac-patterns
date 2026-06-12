using './main.bicep'

param name = 'contoso'
param location = 'eastus'
param environment = 'dev'
param enableServerless = true
param enablePrivateEndpoints = false
param privateEndpointSubnetId = ''
param enableMultiRegionWrite = false
param backupRegion = ''
