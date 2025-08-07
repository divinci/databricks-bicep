@description('Cluster ID for permissions')
param ClusterId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Access control list for cluster')
param AccessControlList array

var permissionsConfig = {
  access_control_list: AccessControlList
}

resource clusterPermissionsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-cluster-permissions-${uniqueString(ClusterId)}'
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
        name: 'CLUSTER_ID'
        value: ClusterId
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Set cluster permissions
      $setResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/permissions/clusters/$($env:CLUSTER_ID)" `
        -Body $env:PERMISSIONS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get cluster permissions
      $permissionsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/permissions/clusters/$($env:CLUSTER_ID)" `
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

@description('The cluster ID')
output ObjectId string = clusterPermissionsCreation.properties.outputs.objectId

@description('The object type')
output ObjectType string = clusterPermissionsCreation.properties.outputs.objectType

@description('The access control list')
output AccessControlList string = clusterPermissionsCreation.properties.outputs.accessControlList
