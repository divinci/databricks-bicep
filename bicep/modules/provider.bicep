@description('Name of the Delta Sharing provider')
param ProviderName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the provider')
param Comment string = ''

@description('Authentication type for the provider')
@allowed(['TOKEN', 'DATABRICKS'])
param AuthenticationType string = 'TOKEN'

@description('Recipient profile string for the provider')
param RecipientProfileStr string = ''

@description('Owner of the provider')
param Owner string = ''

var providerConfig = {
  name: ProviderName
  comment: empty(Comment) ? null : Comment
  authentication_type: AuthenticationType
  recipient_profile_str: empty(RecipientProfileStr) ? null : RecipientProfileStr
  owner: empty(Owner) ? null : Owner
}

resource providerCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-provider-${uniqueString(ProviderName)}'
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
        name: 'PROVIDER_CONFIG'
        value: string(providerConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Delta Sharing provider
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/providers" `
        -Body $env:PROVIDER_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $provider = $createResponse | ConvertFrom-Json
      
      # Get provider details
      $providerDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/providers/$($provider.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $providerDetails = $providerDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        providerName = $providerDetails.name
        comment = $providerDetails.comment
        authenticationType = $providerDetails.authentication_type
        recipientProfileStr = $providerDetails.recipient_profile_str
        owner = $providerDetails.owner
        createdAt = $providerDetails.created_at
        updatedAt = $providerDetails.updated_at
      }
    '''
  }
}

@description('The name of the created provider')
output ProviderName string = providerCreation.properties.outputs.providerName

@description('The comment for the provider')
output Comment string = providerCreation.properties.outputs.comment

@description('The authentication type of the provider')
output AuthenticationType string = providerCreation.properties.outputs.authenticationType

@description('The recipient profile string for the provider')
output RecipientProfileStr string = providerCreation.properties.outputs.recipientProfileStr

@description('The owner of the provider')
output Owner string = providerCreation.properties.outputs.owner

@description('The creation timestamp of the provider')
output CreatedAt int = int(providerCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the provider')
output UpdatedAt int = int(providerCreation.properties.outputs.updatedAt)
