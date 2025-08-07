@description('Name of the secret')
param SecretName string

@description('Name of the secret scope')
param ScopeName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('The secret value')
@secure()
param SecretValue string

var secretConfig = {
  scope: ScopeName
  key: SecretName
  string_value: SecretValue
}

resource secretCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-secret-${uniqueString(ScopeName, SecretName)}'
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
        name: 'SECRET_CONFIG'
        value: string(secretConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create secret
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/secrets/put" `
        -Body $env:SECRET_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $config = $env:SECRET_CONFIG | ConvertFrom-Json
      
      # List secrets to verify creation
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/secrets/list?scope=$($config.scope)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $secrets = ($listResponse | ConvertFrom-Json).secrets
      $secret = $secrets | Where-Object { $_.key -eq $config.key }
      
      if (-not $secret) {
        throw "Failed to find created secret: $($config.key)"
      }
      
      $DeploymentScriptOutputs = @{
        secretName = $config.key
        scopeName = $config.scope
        lastUpdatedTimestamp = $secret.last_updated_timestamp
      }
    '''
  }
}

@description('The name of the created secret')
output SecretName string = secretCreation.properties.outputs.secretName

@description('The name of the secret scope')
output ScopeName string = secretCreation.properties.outputs.scopeName

@description('The last updated timestamp of the secret')
output LastUpdatedTimestamp int = int(secretCreation.properties.outputs.lastUpdatedTimestamp)
