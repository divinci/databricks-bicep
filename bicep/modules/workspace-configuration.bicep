@description('Configuration key')
param ConfigurationKey string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Configuration value')
param ConfigurationValue string

var configurationConfig = {
  (ConfigurationKey): ConfigurationValue
}

resource workspaceConfigurationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-configuration-${uniqueString(ConfigurationKey)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'DATABRICKS_TOKEN'
        secureValue: DatabricksToken
      }
      {
        name: 'WORKSPACE_URL'
        value: WorkspaceUrl
      }
      {
        name: 'CONFIGURATION_CONFIG'
        value: string(configurationConfig)
      }
      {
        name: 'CONFIGURATION_KEY'
        value: ConfigurationKey
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Set workspace configuration
      $setResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PATCH" `
        -UrlPath "/api/2.0/workspace-conf" `
        -Body $env:CONFIGURATION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get workspace configuration
      $getResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace-conf?keys=$($env:CONFIGURATION_KEY)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $configuration = $getResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        configurationKey = $env:CONFIGURATION_KEY
        configurationValue = $configuration.($env:CONFIGURATION_KEY)
      }
    '''
  }
}

@description('The configuration key')
output ConfigurationKey string = workspaceConfigurationCreation.properties.outputs.configurationKey

@description('The configuration value')
output ConfigurationValue string = workspaceConfigurationCreation.properties.outputs.configurationValue
