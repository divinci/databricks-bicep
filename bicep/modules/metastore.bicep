@description('Name of the Unity Catalog metastore')
param MetastoreName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Storage root for the metastore')
param StorageRoot string

@description('Owner of the metastore')
param Owner string = ''

@description('Region for the metastore')
param Region string = ''

@description('Whether to force destroy the metastore')
param ForceDestroy bool = false

@description('Delta sharing scope')
param DeltaSharingScope string = 'INTERNAL'

@description('Delta sharing recipient token lifetime in seconds')
param DeltaSharingRecipientTokenLifetimeInSeconds int = 0

@description('Delta sharing organization name')
param DeltaSharingOrganizationName string = ''

var metastoreConfig = {
  name: MetastoreName
  storage_root: StorageRoot
  owner: empty(Owner) ? null : Owner
  region: empty(Region) ? null : Region
  delta_sharing_scope: DeltaSharingScope
  delta_sharing_recipient_token_lifetime_in_seconds: DeltaSharingRecipientTokenLifetimeInSeconds == 0 ? null : DeltaSharingRecipientTokenLifetimeInSeconds
  delta_sharing_organization_name: empty(DeltaSharingOrganizationName) ? null : DeltaSharingOrganizationName
}

resource metastoreCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-metastore-${uniqueString(MetastoreName)}'
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
        name: 'METASTORE_CONFIG'
        value: string(metastoreConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create metastore
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/metastores" `
        -Body $env:METASTORE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $metastore = $createResponse | ConvertFrom-Json
      
      # Get metastore details
      $metastoreDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/metastores/$($metastore.metastore_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $metastoreDetails = $metastoreDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        metastoreName = $metastoreDetails.name
        metastoreId = $metastoreDetails.metastore_id
        owner = $metastoreDetails.owner
        storageRoot = $metastoreDetails.storage_root
        region = $metastoreDetails.region
        deltaSharingScope = $metastoreDetails.delta_sharing_scope
        deltaSharingOrganizationName = $metastoreDetails.delta_sharing_organization_name
        createdAt = $metastoreDetails.created_at
        updatedAt = $metastoreDetails.updated_at
      }
    '''
  }
}

@description('The name of the created metastore')
output MetastoreName string = metastoreCreation.properties.outputs.metastoreName

@description('The unique ID of the metastore')
output MetastoreId string = metastoreCreation.properties.outputs.metastoreId

@description('The owner of the metastore')
output Owner string = metastoreCreation.properties.outputs.owner

@description('The storage root of the metastore')
output StorageRoot string = metastoreCreation.properties.outputs.storageRoot

@description('The region of the metastore')
output Region string = metastoreCreation.properties.outputs.region

@description('The delta sharing scope')
output DeltaSharingScope string = metastoreCreation.properties.outputs.deltaSharingScope

@description('The delta sharing organization name')
output DeltaSharingOrganizationName string = metastoreCreation.properties.outputs.deltaSharingOrganizationName

@description('The creation timestamp of the metastore')
output CreatedAt int = int(metastoreCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the metastore')
output UpdatedAt int = int(metastoreCreation.properties.outputs.updatedAt)
