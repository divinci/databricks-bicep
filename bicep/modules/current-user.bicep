@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

resource currentUserCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-current-user-${uniqueString(WorkspaceUrl)}'
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
      
      # Get current user
      $userResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/scim/v2/Me" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $user = $userResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        userId = $user.id
        userName = $user.userName
        displayName = $user.displayName
        active = $user.active
        emails = ($user.emails | ConvertTo-Json -Compress)
        groups = ($user.groups | ConvertTo-Json -Compress)
        roles = ($user.roles | ConvertTo-Json -Compress)
        entitlements = ($user.entitlements | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The current user ID')
output UserId string = currentUserCreation.properties.outputs.userId

@description('The current user name')
output UserName string = currentUserCreation.properties.outputs.userName

@description('The current user display name')
output DisplayName string = currentUserCreation.properties.outputs.displayName

@description('Whether the current user is active')
output Active bool = bool(currentUserCreation.properties.outputs.active)

@description('The current user emails')
output Emails string = currentUserCreation.properties.outputs.emails

@description('The current user groups')
output Groups string = currentUserCreation.properties.outputs.groups

@description('The current user roles')
output Roles string = currentUserCreation.properties.outputs.roles

@description('The current user entitlements')
output Entitlements string = currentUserCreation.properties.outputs.entitlements
