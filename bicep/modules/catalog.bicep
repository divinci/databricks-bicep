@description('Name of the Unity Catalog catalog')
param CatalogName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the catalog')
param Comment string = ''

@description('Storage root for the catalog')
param StorageRoot string = ''

@description('Properties for the catalog')
param Properties object = {}

@description('Owner of the catalog')
param Owner string = ''

@description('Whether the catalog is isolated')
param IsolationMode string = 'OPEN'

var catalogConfig = {
  name: CatalogName
  comment: empty(Comment) ? null : Comment
  storage_root: empty(StorageRoot) ? null : StorageRoot
  properties: empty(Properties) ? null : Properties
  owner: empty(Owner) ? null : Owner
  isolation_mode: IsolationMode
}

resource catalogCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-catalog-${uniqueString(CatalogName)}'
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
        name: 'CATALOG_CONFIG'
        value: string(catalogConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create catalog
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/catalogs" `
        -Body $env:CATALOG_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $catalog = $createResponse | ConvertFrom-Json
      
      # Get catalog details
      $catalogDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/catalogs/$($catalog.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $catalogDetails = $catalogDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        catalogName = $catalogDetails.name
        catalogId = $catalogDetails.catalog_id
        owner = $catalogDetails.owner
        comment = $catalogDetails.comment
        storageRoot = $catalogDetails.storage_root
        isolationMode = $catalogDetails.isolation_mode
        createdAt = $catalogDetails.created_at
        updatedAt = $catalogDetails.updated_at
      }
    '''
  }
}

@description('The name of the created catalog')
output CatalogName string = catalogCreation.properties.outputs.catalogName

@description('The unique ID of the catalog')
output CatalogId string = catalogCreation.properties.outputs.catalogId

@description('The owner of the catalog')
output Owner string = catalogCreation.properties.outputs.owner

@description('The comment for the catalog')
output Comment string = catalogCreation.properties.outputs.comment

@description('The storage root of the catalog')
output StorageRoot string = catalogCreation.properties.outputs.storageRoot

@description('The isolation mode of the catalog')
output IsolationMode string = catalogCreation.properties.outputs.isolationMode

@description('The creation timestamp of the catalog')
output CreatedAt int = int(catalogCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the catalog')
output UpdatedAt int = int(catalogCreation.properties.outputs.updatedAt)
