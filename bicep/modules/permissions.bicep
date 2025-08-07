@description('Object ID to set permissions for')
param ObjectId string

@description('Object type (cluster, job, instance-pool, etc.)')
@allowed(['cluster', 'job', 'instance-pool', 'notebook', 'directory', 'repo'])
param ObjectType string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Access control list with permissions')
param AccessControlList array

var permissionsConfig = {
  access_control_list: AccessControlList
}

var apiEndpoint = ObjectType == 'cluster' ? '/api/2.0/permissions/clusters/${ObjectId}' :
                  ObjectType == 'job' ? '/api/2.0/permissions/jobs/${ObjectId}' :
                  ObjectType == 'instance-pool' ? '/api/2.0/permissions/instance-pools/${ObjectId}' :
                  ObjectType == 'notebook' ? '/api/2.0/permissions/notebooks/${ObjectId}' :
                  ObjectType == 'directory' ? '/api/2.0/permissions/directories/${ObjectId}' :
                  ObjectType == 'repo' ? '/api/2.0/permissions/repos/${ObjectId}' :
                  '/api/2.0/permissions/${ObjectType}/${ObjectId}'

resource permissionsUpdate 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'update-databricks-permissions-${uniqueString(ObjectId, ObjectType)}'
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
        name: 'API_ENDPOINT'
        value: apiEndpoint
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
      
      # Update permissions
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PATCH" `
        -UrlPath $env:API_ENDPOINT `
        -Body $env:PERMISSIONS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get current permissions
      $currentPermissionsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath $env:API_ENDPOINT `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $currentPermissions = $currentPermissionsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        objectId = $env:OBJECT_ID
        objectType = $env:OBJECT_TYPE
        accessControlListCount = $currentPermissions.access_control_list.Count
      }
    '''
  }
}

@description('The object ID that permissions were set for')
output ObjectId string = permissionsUpdate.properties.outputs.objectId

@description('The object type that permissions were set for')
output ObjectType string = permissionsUpdate.properties.outputs.objectType

@description('Number of access control entries')
output AccessControlListCount int = int(permissionsUpdate.properties.outputs.accessControlListCount)
