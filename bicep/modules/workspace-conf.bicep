@description('Configuration key for the workspace setting')
param ConfigKey string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Configuration value for the workspace setting')
param ConfigValue string

var configData = {
  (ConfigKey): ConfigValue
}

resource workspaceConfCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-conf-${uniqueString(ConfigKey)}'
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
        name: 'CONFIG_DATA'
        value: string(configData)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Update workspace configuration
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PATCH" `
        -UrlPath "/api/2.0/workspace-conf" `
        -Body $env:CONFIG_DATA `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get workspace configuration
      $configResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace-conf" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $config = $configResponse | ConvertFrom-Json
      $configData = $env:CONFIG_DATA | ConvertFrom-Json
      $configKey = ($configData | Get-Member -MemberType NoteProperty)[0].Name
      $configValue = $config.$configKey
      
      $DeploymentScriptOutputs = @{
        configKey = $configKey
        configValue = $configValue
      }
    '''
  }
}

@description('The configuration key')
output ConfigKey string = workspaceConfCreation.properties.outputs.configKey

@description('The configuration value')
output ConfigValue string = workspaceConfCreation.properties.outputs.configValue
