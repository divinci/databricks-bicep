@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

resource workspaceInfoCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-workspace-info-${uniqueString(WorkspaceUrl)}'
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
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Get workspace configuration
      $configResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace-conf" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $config = $configResponse | ConvertFrom-Json
      
      # Get current user to determine workspace access
      $userResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/scim/v2/Me" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $user = $userResponse | ConvertFrom-Json
      
      # Get workspace status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=/" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        workspaceUrl = $env:WORKSPACE_URL
        currentUserId = $user.id
        currentUserName = $user.userName
        workspaceConfiguration = ($config | ConvertTo-Json -Compress)
        rootObjectId = $status.object_id
        rootObjectType = $status.object_type
        isAccessible = $true
      }
    '''
  }
}

@description('The workspace URL')
output WorkspaceUrl string = workspaceInfoCreation.properties.outputs.workspaceUrl

@description('The current user ID')
output CurrentUserId string = workspaceInfoCreation.properties.outputs.currentUserId

@description('The current user name')
output CurrentUserName string = workspaceInfoCreation.properties.outputs.currentUserName

@description('The workspace configuration')
output WorkspaceConfiguration string = workspaceInfoCreation.properties.outputs.workspaceConfiguration

@description('The root object ID')
output RootObjectId int = int(workspaceInfoCreation.properties.outputs.rootObjectId)

@description('The root object type')
output RootObjectType string = workspaceInfoCreation.properties.outputs.rootObjectType

@description('Whether the workspace is accessible')
output IsAccessible bool = bool(workspaceInfoCreation.properties.outputs.isAccessible)
