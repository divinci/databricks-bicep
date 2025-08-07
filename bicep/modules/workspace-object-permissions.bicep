@description('Object ID for permissions')
param ObjectId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Object type')
@allowed(['notebook', 'directory', 'library', 'repo', 'file'])
param ObjectType string

@description('Access control list')
param AccessControlList array

var permissionsConfig = {
  access_control_list: AccessControlList
}

resource workspaceObjectPermissionsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-object-permissions-${uniqueString(ObjectId)}'
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
        name: 'PERMISSIONS_CONFIG'
        value: string(permissionsConfig)
      }
      {
        name: 'OBJECT_ID'
        value: ObjectId
      }
      {
        name: 'OBJECT_TYPE'
        value: ObjectType
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Set workspace object permissions
      $setResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/permissions/$($env:OBJECT_TYPE)/$($env:OBJECT_ID)" `
        -Body $env:PERMISSIONS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get workspace object permissions
      $permissionsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/permissions/$($env:OBJECT_TYPE)/$($env:OBJECT_ID)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $permissions = $permissionsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        objectId = $permissions.object_id
        objectType = $permissions.object_type
        accessControlList = ($permissions.access_control_list | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The object ID')
output ObjectId string = workspaceObjectPermissionsCreation.properties.outputs.objectId

@description('The object type')
output ObjectType string = workspaceObjectPermissionsCreation.properties.outputs.objectType

@description('The access control list')
output AccessControlList string = workspaceObjectPermissionsCreation.properties.outputs.accessControlList
