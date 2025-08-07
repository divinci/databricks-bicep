@description('Principal ID for the MWS permission assignment')
param PrincipalId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Account ID for the permission assignment')
param AccountId string

@description('Permissions to assign')
param Permissions array

var assignmentConfig = {
  principal_id: PrincipalId
  permissions: Permissions
}

resource mwsPermissionAssignmentCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-permission-assignment-${uniqueString(PrincipalId)}'
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
        name: 'ACCOUNT_ID'
        value: AccountId
      }
      {
        name: 'ASSIGNMENT_CONFIG'
        value: string(assignmentConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MWS permission assignment
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/scim/v2/Users/$($env:ASSIGNMENT_CONFIG | ConvertFrom-Json).principal_id" `
        -Body $env:ASSIGNMENT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $assignment = $createResponse | ConvertFrom-Json
      
      # Get assignment details
      $assignmentDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/scim/v2/Users/$($assignment.id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $assignmentDetails = $assignmentDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        principalId = $assignmentDetails.id
        permissions = ($assignmentDetails.entitlements | ConvertTo-Json -Compress)
        accountId = $env:ACCOUNT_ID
      }
    '''
  }
}

@description('The principal ID of the permission assignment')
output PrincipalId string = mwsPermissionAssignmentCreation.properties.outputs.principalId

@description('The permissions of the assignment')
output Permissions string = mwsPermissionAssignmentCreation.properties.outputs.permissions

@description('The account ID')
output AccountId string = mwsPermissionAssignmentCreation.properties.outputs.accountId
