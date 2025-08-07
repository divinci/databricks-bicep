@description('Name of the Unity Catalog volume')
param VolumeName string

@description('Catalog name for the volume')
param CatalogName string

@description('Schema name for the volume')
param SchemaName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Volume type')
@allowed(['MANAGED', 'EXTERNAL'])
param VolumeType string

@description('Storage location for external volumes')
param StorageLocation string = ''

@description('Comment for the volume')
param Comment string = ''

@description('Owner of the volume')
param Owner string = ''

var volumeConfig = {
  name: VolumeName
  catalog_name: CatalogName
  schema_name: SchemaName
  volume_type: VolumeType
  storage_location: empty(StorageLocation) ? null : StorageLocation
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
}

resource volumeCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-volume-${uniqueString(VolumeName)}'
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
        name: 'VOLUME_CONFIG'
        value: string(volumeConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Unity Catalog volume
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/volumes" `
        -Body $env:VOLUME_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $volume = $createResponse | ConvertFrom-Json
      
      # Get volume details
      $volumeDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/volumes/$($volume.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $volumeDetails = $volumeDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        volumeName = $volumeDetails.name
        catalogName = $volumeDetails.catalog_name
        schemaName = $volumeDetails.schema_name
        fullName = $volumeDetails.full_name
        volumeType = $volumeDetails.volume_type
        storageLocation = $volumeDetails.storage_location
        comment = $volumeDetails.comment
        owner = $volumeDetails.owner
        createdAt = $volumeDetails.created_at
        updatedAt = $volumeDetails.updated_at
        volumeId = $volumeDetails.volume_id
      }
    '''
  }
}

@description('The name of the created volume')
output VolumeName string = volumeCreation.properties.outputs.volumeName

@description('The catalog name of the volume')
output CatalogName string = volumeCreation.properties.outputs.catalogName

@description('The schema name of the volume')
output SchemaName string = volumeCreation.properties.outputs.schemaName

@description('The full name of the volume')
output FullName string = volumeCreation.properties.outputs.fullName

@description('The type of the volume')
output VolumeType string = volumeCreation.properties.outputs.volumeType

@description('The storage location of the volume')
output StorageLocation string = volumeCreation.properties.outputs.storageLocation

@description('The comment for the volume')
output Comment string = volumeCreation.properties.outputs.comment

@description('The owner of the volume')
output Owner string = volumeCreation.properties.outputs.owner

@description('The creation timestamp of the volume')
output CreatedAt int = int(volumeCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the volume')
output UpdatedAt int = int(volumeCreation.properties.outputs.updatedAt)

@description('The unique ID of the volume')
output VolumeId string = volumeCreation.properties.outputs.volumeId
