@description('Databricks Custom Resource Provider for Infrastructure Automation')
param providerName string = 'databricks-infrastructure-provider'
param location string = resourceGroup().location
param databricksWorkspaceUrl string
param functionAppName string = 'databricks-provider-functions'

// Storage account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'dbxprovider${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// App Service Plan for Azure Functions
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Azure Function App to handle Databricks API calls
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'DATABRICKS_WORKSPACE_URL'
          value: databricksWorkspaceUrl
        }
        {
          name: 'DATABRICKS_TOKEN'
          value: '@Microsoft.KeyVault(SecretUri=https://your-keyvault.vault.azure.net/secrets/databricks-token/)'
        }
      ]
    }
    httpsOnly: true
  }
}

// Databricks Custom Resource Provider
resource databricksProvider 'Microsoft.CustomProviders/resourceProviders@2018-09-01-preview' = {
  name: providerName
  location: location
  properties: {
    actions: [
      {
        name: 'startCluster'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/clusters/start'
        routingType: 'Proxy'
      }
      {
        name: 'stopCluster'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/clusters/stop'
        routingType: 'Proxy'
      }
      {
        name: 'restartCluster'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/clusters/restart'
        routingType: 'Proxy'
      }
      {
        name: 'runJob'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/jobs/run'
        routingType: 'Proxy'
      }
      {
        name: 'getClusterStatus'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/clusters/status'
        routingType: 'Proxy'
      }
    ]
    resourceTypes: [
      {
        name: 'clusters'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/clusters'
        routingType: 'Proxy,Cache'
      }
      {
        name: 'jobs'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/jobs'
        routingType: 'Proxy,Cache'
      }
      {
        name: 'instancePools'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/instance-pools'
        routingType: 'Proxy,Cache'
      }
      {
        name: 'notebooks'
        endpoint: 'https://${functionApp.properties.defaultHostName}/api/notebooks'
        routingType: 'Proxy,Cache'
      }
    ]
  }
}

output providerName string = databricksProvider.name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
