@description('Name of the Delta Sharing recipient')
param RecipientName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the recipient')
param Comment string = ''

@description('Sharing identifier for the recipient')
param SharingIdentifier string = ''

@description('Authentication type for the recipient')
@allowed(['TOKEN', 'DATABRICKS'])
param AuthenticationType string = 'TOKEN'

@description('Data recipient global metastore ID')
param DataRecipientGlobalMetastoreId string = ''

@description('Owner of the recipient')
param Owner string = ''

@description('IP access list for the recipient')
param IpAccessList object = {}

@description('Properties for the recipient')
param PropertiesKvpairs object = {}

var recipientConfig = {
  name: RecipientName
  comment: empty(Comment) ? null : Comment
  sharing_identifier: empty(SharingIdentifier) ? null : SharingIdentifier
  authentication_type: AuthenticationType
  data_recipient_global_metastore_id: empty(DataRecipientGlobalMetastoreId) ? null : DataRecipientGlobalMetastoreId
  owner: empty(Owner) ? null : Owner
  ip_access_list: empty(IpAccessList) ? null : IpAccessList
  properties_kvpairs: empty(PropertiesKvpairs) ? null : PropertiesKvpairs
}

resource recipientCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-recipient-${uniqueString(RecipientName)}'
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
        name: 'RECIPIENT_CONFIG'
        value: string(recipientConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Delta Sharing recipient
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/recipients" `
        -Body $env:RECIPIENT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $recipient = $createResponse | ConvertFrom-Json
      
      # Get recipient details
      $recipientDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/recipients/$($recipient.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $recipientDetails = $recipientDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        recipientName = $recipientDetails.name
        comment = $recipientDetails.comment
        sharingIdentifier = $recipientDetails.sharing_identifier
        authenticationType = $recipientDetails.authentication_type
        dataRecipientGlobalMetastoreId = $recipientDetails.data_recipient_global_metastore_id
        owner = $recipientDetails.owner
        createdAt = $recipientDetails.created_at
        updatedAt = $recipientDetails.updated_at
      }
    '''
  }
}

@description('The name of the created recipient')
output RecipientName string = recipientCreation.properties.outputs.recipientName

@description('The comment for the recipient')
output Comment string = recipientCreation.properties.outputs.comment

@description('The sharing identifier for the recipient')
output SharingIdentifier string = recipientCreation.properties.outputs.sharingIdentifier

@description('The authentication type of the recipient')
output AuthenticationType string = recipientCreation.properties.outputs.authenticationType

@description('The data recipient global metastore ID')
output DataRecipientGlobalMetastoreId string = recipientCreation.properties.outputs.dataRecipientGlobalMetastoreId

@description('The owner of the recipient')
output Owner string = recipientCreation.properties.outputs.owner

@description('The creation timestamp of the recipient')
output CreatedAt int = int(recipientCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the recipient')
output UpdatedAt int = int(recipientCreation.properties.outputs.updatedAt)
