@description('Principal name for the grant')
param Principal string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Securable type for the grant')
@allowed(['CATALOG', 'SCHEMA', 'TABLE', 'VIEW', 'FUNCTION', 'VOLUME', 'MODEL', 'SHARE', 'RECIPIENT', 'PROVIDER', 'EXTERNAL_LOCATION', 'STORAGE_CREDENTIAL', 'METASTORE'])
param SecurableType string

@description('Full name of the securable object')
param SecurableName string

@description('Privileges to grant')
param Privileges array

var grantConfig = {
  principal: Principal
  securable_type: SecurableType
  securable_name: SecurableName
  privileges: Privileges
}

resource grantCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-grant-${uniqueString(Principal, SecurableName)}'
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
        name: 'GRANT_CONFIG'
        value: string(grantConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Unity Catalog grant
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PATCH" `
        -UrlPath "/api/2.1/unity-catalog/permissions/$($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_type)/$($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_name)" `
        -Body $env:GRANT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $grant = $createResponse | ConvertFrom-Json
      
      # Get grant details by listing permissions
      $permissionsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/permissions/$($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_type)/$($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $permissions = $permissionsResponse | ConvertFrom-Json
      $grantDetails = $permissions.privilege_assignments | Where-Object { $_.principal -eq ($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty principal) } | Select-Object -First 1
      
      $DeploymentScriptOutputs = @{
        principal = $grantDetails.principal
        securableType = ($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_type)
        securableName = ($env:GRANT_CONFIG | ConvertFrom-Json | Select-Object -ExpandProperty securable_name)
        privileges = ($grantDetails.privileges -join ",")
      }
    '''
  }
}

@description('The principal of the grant')
output Principal string = grantCreation.properties.outputs.principal

@description('The securable type of the grant')
output SecurableType string = grantCreation.properties.outputs.securableType

@description('The securable name of the grant')
output SecurableName string = grantCreation.properties.outputs.securableName

@description('The privileges granted (comma-separated)')
output Privileges string = grantCreation.properties.outputs.privileges
