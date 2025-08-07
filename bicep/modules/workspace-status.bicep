@description('Workspace path to check status')
param WorkspacePath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

resource workspaceStatusCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-workspace-status-${uniqueString(WorkspacePath)}'
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
        name: 'WORKSPACE_PATH'
        value: WorkspacePath
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # URL encode the path
      $encodedPath = [System.Web.HttpUtility]::UrlEncode($env:WORKSPACE_PATH)
      
      # Get workspace object status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$encodedPath" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        path = $status.path
        objectId = $status.object_id
        objectType = $status.object_type
        language = if ($status.language) { $status.language } else { "" }
        createdAt = if ($status.created_at) { $status.created_at } else { 0 }
        modifiedAt = if ($status.modified_at) { $status.modified_at } else { 0 }
        size = if ($status.size) { $status.size } else { 0 }
        exists = $true
      }
    '''
  }
}

@description('The workspace path')
output Path string = workspaceStatusCreation.properties.outputs.path

@description('The object ID')
output ObjectId int = int(workspaceStatusCreation.properties.outputs.objectId)

@description('The object type')
output ObjectType string = workspaceStatusCreation.properties.outputs.objectType

@description('The object language')
output Language string = workspaceStatusCreation.properties.outputs.language

@description('The creation timestamp')
output CreatedAt int = int(workspaceStatusCreation.properties.outputs.createdAt)

@description('The modification timestamp')
output ModifiedAt int = int(workspaceStatusCreation.properties.outputs.modifiedAt)

@description('The object size')
output Size int = int(workspaceStatusCreation.properties.outputs.size)

@description('Whether the object exists')
output Exists bool = bool(workspaceStatusCreation.properties.outputs.exists)
