@description('Name of the custom app integration')
param IntegrationName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Redirect URLs for the custom app')
param RedirectUrls array

@description('Confidential client setting')
param Confidential bool = true

@description('Token access policy for the custom app')
param TokenAccessPolicy object = {}

@description('Scopes for the custom app')
param Scopes array = []

var integrationConfig = {
  name: IntegrationName
  redirect_urls: RedirectUrls
  confidential: Confidential
  token_access_policy: empty(TokenAccessPolicy) ? {} : TokenAccessPolicy
  scopes: Scopes
}

resource customAppIntegrationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-custom-app-integration-${uniqueString(IntegrationName)}'
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
        name: 'INTEGRATION_CONFIG'
        value: string(integrationConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create custom app integration
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/oauth2/custom-app-integrations" `
        -Body $env:INTEGRATION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $integration = $createResponse | ConvertFrom-Json
      
      # Get integration details
      $integrationDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/oauth2/custom-app-integrations/$($integration.integration_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $integrationDetails = $integrationDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        integrationId = $integrationDetails.integration_id
        integrationName = $integrationDetails.name
        clientId = $integrationDetails.client_id
        clientSecret = $integrationDetails.client_secret
        redirectUrls = ($integrationDetails.redirect_urls | ConvertTo-Json -Compress)
        confidential = $integrationDetails.confidential
        tokenAccessPolicy = ($integrationDetails.token_access_policy | ConvertTo-Json -Compress)
        scopes = ($integrationDetails.scopes | ConvertTo-Json -Compress)
        createdBy = $integrationDetails.created_by
        createdTime = $integrationDetails.created_time
      }
    '''
  }
}

@description('The ID of the created custom app integration')
output IntegrationId string = customAppIntegrationCreation.properties.outputs.integrationId

@description('The name of the custom app integration')
output IntegrationName string = customAppIntegrationCreation.properties.outputs.integrationName

@description('The client ID of the custom app integration')
output ClientId string = customAppIntegrationCreation.properties.outputs.clientId

@description('The client secret of the custom app integration')
@secure()
output ClientSecret string = customAppIntegrationCreation.properties.outputs.clientSecret

@description('The redirect URLs of the custom app integration')
output RedirectUrls string = customAppIntegrationCreation.properties.outputs.redirectUrls

@description('Whether the custom app integration is confidential')
output Confidential bool = bool(customAppIntegrationCreation.properties.outputs.confidential)

@description('The token access policy of the custom app integration')
output TokenAccessPolicy string = customAppIntegrationCreation.properties.outputs.tokenAccessPolicy

@description('The scopes of the custom app integration')
output Scopes string = customAppIntegrationCreation.properties.outputs.scopes

@description('The user who created the custom app integration')
output CreatedBy int = int(customAppIntegrationCreation.properties.outputs.createdBy)

@description('The creation time of the custom app integration')
output CreatedTime int = int(customAppIntegrationCreation.properties.outputs.createdTime)
