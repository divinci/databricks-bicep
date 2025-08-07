@description('Job ID for permissions')
param JobId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Access control list for job')
param AccessControlList array

var permissionsConfig = {
  access_control_list: AccessControlList
}

resource jobPermissionsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-job-permissions-${uniqueString(JobId)}'
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
        name: 'JOB_ID'
        value: JobId
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Set job permissions
      $setResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/permissions/jobs/$($env:JOB_ID)" `
        -Body $env:PERMISSIONS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get job permissions
      $permissionsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/permissions/jobs/$($env:JOB_ID)" `
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

@description('The job ID')
output ObjectId string = jobPermissionsCreation.properties.outputs.objectId

@description('The object type')
output ObjectType string = jobPermissionsCreation.properties.outputs.objectType

@description('The access control list')
output AccessControlList string = jobPermissionsCreation.properties.outputs.accessControlList
