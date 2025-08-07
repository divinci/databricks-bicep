@description('Private access settings name')
param PrivateAccessSettingsName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Account ID for the private access settings')
param AccountId string

@description('Region for the private access settings')
param Region string

@description('Public access enabled flag')
param PublicAccessEnabled bool = false

@description('Private access level')
@allowed(['ACCOUNT', 'ENDPOINT'])
param PrivateAccessLevel string = 'ACCOUNT'

@description('Allowed VPC endpoint IDs')
param AllowedVpcEndpointIds array = []

var privateAccessConfig = {
  private_access_settings_name: PrivateAccessSettingsName
  region: Region
  public_access_enabled: PublicAccessEnabled
  private_access_level: PrivateAccessLevel
  allowed_vpc_endpoint_ids: AllowedVpcEndpointIds
}

resource mwsPrivateAccessSettingsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-private-access-${uniqueString(PrivateAccessSettingsName)}'
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
        name: 'PRIVATE_ACCESS_CONFIG'
        value: string(privateAccessConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MWS private access settings
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/private-access-settings" `
        -Body $env:PRIVATE_ACCESS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $privateAccess = $createResponse | ConvertFrom-Json
      
      # Get private access settings details
      $privateAccessDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/private-access-settings/$($privateAccess.private_access_settings_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $privateAccessDetails = $privateAccessDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        privateAccessSettingsId = $privateAccessDetails.private_access_settings_id
        privateAccessSettingsName = $privateAccessDetails.private_access_settings_name
        region = $privateAccessDetails.region
        publicAccessEnabled = $privateAccessDetails.public_access_enabled
        privateAccessLevel = $privateAccessDetails.private_access_level
        allowedVpcEndpointIds = ($privateAccessDetails.allowed_vpc_endpoint_ids | ConvertTo-Json -Compress)
        accountId = $privateAccessDetails.account_id
      }
    '''
  }
}

@description('The private access settings ID')
output PrivateAccessSettingsId string = mwsPrivateAccessSettingsCreation.properties.outputs.privateAccessSettingsId

@description('The private access settings name')
output PrivateAccessSettingsName string = mwsPrivateAccessSettingsCreation.properties.outputs.privateAccessSettingsName

@description('The region of the private access settings')
output Region string = mwsPrivateAccessSettingsCreation.properties.outputs.region

@description('Whether public access is enabled')
output PublicAccessEnabled bool = bool(mwsPrivateAccessSettingsCreation.properties.outputs.publicAccessEnabled)

@description('The private access level')
output PrivateAccessLevel string = mwsPrivateAccessSettingsCreation.properties.outputs.privateAccessLevel

@description('The allowed VPC endpoint IDs')
output AllowedVpcEndpointIds string = mwsPrivateAccessSettingsCreation.properties.outputs.allowedVpcEndpointIds

@description('The account ID')
output AccountId string = mwsPrivateAccessSettingsCreation.properties.outputs.accountId
