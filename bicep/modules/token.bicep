@description('Comment for the personal access token')
param Comment string

@description('Databricks Personal Access Token (for creating new tokens)')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Lifetime of the token in seconds (0 for no expiration)')
param LifetimeSeconds int = 0

var tokenConfig = {
  comment: Comment
  lifetime_seconds: LifetimeSeconds == 0 ? null : LifetimeSeconds
}

resource tokenCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-token-${uniqueString(Comment)}'
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
        name: 'TOKEN_CONFIG'
        value: string(tokenConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create token
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/token/create" `
        -Body $env:TOKEN_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $token = $createResponse | ConvertFrom-Json
      
      # List tokens to get details
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/token/list" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $tokens = ($listResponse | ConvertFrom-Json).token_infos
      $createdToken = $tokens | Where-Object { $_.token_id -eq $token.token_info.token_id }
      
      $DeploymentScriptOutputs = @{
        tokenId = $token.token_info.token_id
        comment = $createdToken.comment
        creationTime = $createdToken.creation_time
        expiryTime = $createdToken.expiry_time
        # Note: The actual token value is not returned for security reasons
      }
    '''
  }
}

@description('The ID of the created token')
output TokenId string = tokenCreation.properties.outputs.tokenId

@description('The comment associated with the token')
output Comment string = tokenCreation.properties.outputs.comment

@description('The creation timestamp of the token')
output CreationTime int = int(tokenCreation.properties.outputs.creationTime)

@description('The expiry timestamp of the token (if set)')
output ExpiryTime int = int(tokenCreation.properties.outputs.expiryTime)
