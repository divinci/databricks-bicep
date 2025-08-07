@description('Complete Databricks Infrastructure Deployment')
param environment string = 'production'
param databricksWorkspaceUrl string
param location string = resourceGroup().location

// Deploy Databricks Custom Resource Provider
module databricksProvider 'databricks-provider.bicep' = {
  name: 'databricks-provider-deployment'
  params: {
    location: location
    databricksWorkspaceUrl: databricksWorkspaceUrl
  }
}

// Deploy Databricks Infrastructure
module databricksInfrastructure 'databricks-infrastructure.bicep' = {
  name: 'databricks-infrastructure-deployment'
  params: {
    databricksProviderName: databricksProvider.outputs.providerName
    environment: environment
    clusterConfig: {
      nodeTypeId: 'Standard_DS3_v2'
      numWorkers: 3
      sparkVersion: '15.4.x-scala2.12'
      runtimeEngine: 'STANDARD'
    }
  }
  dependsOn: [
    databricksProvider
  ]
}

// Start the production cluster after deployment
module startCluster 'databricks-operations.bicep' = {
  name: 'start-production-cluster'
  params: {
    databricksProviderName: databricksProvider.outputs.providerName
    clusterId: databricksInfrastructure.outputs.productionClusterId
    operationType: 'start'
  }
  dependsOn: [
    databricksInfrastructure
  ]
}

output databricksProviderName string = databricksProvider.outputs.providerName
output functionAppUrl string = databricksProvider.outputs.functionAppUrl
output productionClusterId string = databricksInfrastructure.outputs.productionClusterId
output mlClusterId string = databricksInfrastructure.outputs.mlClusterId
output etlJobId string = databricksInfrastructure.outputs.etlJobId
