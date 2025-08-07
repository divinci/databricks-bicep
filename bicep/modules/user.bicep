@description('Username (email) for the Databricks user')
param UserName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Display name for the user')
param DisplayName string = ''

@description('Whether the user is active')
param Active bool = true

@description('List of entitlements for the user')
param Entitlements array = []

@description('External ID for the user (for SCIM)')
param ExternalId string = ''

var userConfig = {
  userName: UserName
  displayName: empty(DisplayName) ? UserName : DisplayName
  active: Active
  entitlements: [for entitlement in Entitlements: {
    value: entitlement
  }]
  externalId: empty(ExternalId) ? null : ExternalId
}

resource userCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-user-${uniqueString(UserName)}'
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
        name: 'USER_CONFIG'
        value: string(userConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create user
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/preview/scim/v2/Users" `
        -Body $env:USER_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $user = $createResponse | ConvertFrom-Json
      $userId = $user.id
      
      # Get user details
      $userDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/scim/v2/Users/$userId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $userDetails = $userDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        userId = $userId
        userName = $userDetails.userName
        displayName = $userDetails.displayName
        active = $userDetails.active
      }
    '''
  }
}

@description('The ID of the created user')
output UserId string = userCreation.properties.outputs.userId

@description('The username of the created user')
output UserName string = userCreation.properties.outputs.userName

@description('The display name of the user')
output DisplayName string = userCreation.properties.outputs.displayName

@description('Whether the user is active')
output Active bool = bool(userCreation.properties.outputs.active)
