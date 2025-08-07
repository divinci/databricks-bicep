@description('Application ID for the OBO token')
param ApplicationId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the OBO token')
param Comment string = ''

@description('Lifetime seconds for the OBO token')
param LifetimeSeconds int = 0

var tokenConfig = {
  application_id: ApplicationId
  comment: empty(Comment) ? null : Comment
  lifetime_seconds: LifetimeSeconds == 0 ? null : LifetimeSeconds
}

resource oboTokenCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-obo-token-${uniqueString(ApplicationId)}'
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
      
      # Create OBO token
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/token/create" `
        -Body $env:TOKEN_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $token = $createResponse | ConvertFrom-Json
      
      # Get token details
      $tokenDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/token/list" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $tokenList = $tokenDetailsResponse | ConvertFrom-Json
      $tokenDetails = $tokenList.token_infos | Where-Object { $_.token_id -eq $token.token_info.token_id }
      
      $DeploymentScriptOutputs = @{
        tokenId = $tokenDetails.token_id
        applicationId = $tokenDetails.application_id
        comment = $tokenDetails.comment
        creationTime = $tokenDetails.creation_time
        expiryTime = $tokenDetails.expiry_time
        tokenValue = $token.token_value
      }
    '''
  }
}

@description('The ID of the created OBO token')
output TokenId string = oboTokenCreation.properties.outputs.tokenId

@description('The application ID of the OBO token')
output ApplicationId string = oboTokenCreation.properties.outputs.applicationId

@description('The comment of the OBO token')
output Comment string = oboTokenCreation.properties.outputs.comment

@description('The creation time of the OBO token')
output CreationTime int = int(oboTokenCreation.properties.outputs.creationTime)

@description('The expiry time of the OBO token')
output ExpiryTime int = int(oboTokenCreation.properties.outputs.expiryTime)

@description('The token value of the OBO token')
@secure()
output TokenValue string = oboTokenCreation.properties.outputs.tokenValue
