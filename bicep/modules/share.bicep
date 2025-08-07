@description('Name of the Delta Sharing share')
param ShareName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the share')
param Comment string = ''

@description('Owner of the share')
param Owner string = ''

@description('Storage root for the share')
param StorageRoot string = ''

@description('Storage location for the share')
param StorageLocation string = ''

var shareConfig = {
  name: ShareName
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  storage_root: empty(StorageRoot) ? null : StorageRoot
  storage_location: empty(StorageLocation) ? null : StorageLocation
}

resource shareCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-share-${uniqueString(ShareName)}'
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
        name: 'SHARE_CONFIG'
        value: string(shareConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Delta Sharing share
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/shares" `
        -Body $env:SHARE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $share = $createResponse | ConvertFrom-Json
      
      # Get share details
      $shareDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/shares/$($share.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $shareDetails = $shareDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        shareName = $shareDetails.name
        shareId = $shareDetails.share_id
        owner = $shareDetails.owner
        comment = $shareDetails.comment
        storageRoot = $shareDetails.storage_root
        storageLocation = $shareDetails.storage_location
        createdAt = $shareDetails.created_at
        updatedAt = $shareDetails.updated_at
      }
    '''
  }
}

@description('The name of the created share')
output ShareName string = shareCreation.properties.outputs.shareName

@description('The unique ID of the share')
output ShareId string = shareCreation.properties.outputs.shareId

@description('The owner of the share')
output Owner string = shareCreation.properties.outputs.owner

@description('The comment for the share')
output Comment string = shareCreation.properties.outputs.comment

@description('The storage root of the share')
output StorageRoot string = shareCreation.properties.outputs.storageRoot

@description('The storage location of the share')
output StorageLocation string = shareCreation.properties.outputs.storageLocation

@description('The creation timestamp of the share')
output CreatedAt int = int(shareCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the share')
output UpdatedAt int = int(shareCreation.properties.outputs.updatedAt)
