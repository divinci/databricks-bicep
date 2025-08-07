@description('Name of the Unity Catalog schema')
param SchemaName string

@description('Name of the parent catalog')
param CatalogName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the schema')
param Comment string = ''

@description('Properties for the schema')
param Properties object = {}

@description('Owner of the schema')
param Owner string = ''

@description('Storage root for the schema')
param StorageRoot string = ''

var schemaConfig = {
  name: SchemaName
  catalog_name: CatalogName
  comment: empty(Comment) ? null : Comment
  properties: empty(Properties) ? null : Properties
  owner: empty(Owner) ? null : Owner
  storage_root: empty(StorageRoot) ? null : StorageRoot
}

resource schemaCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-schema-${uniqueString(CatalogName, SchemaName)}'
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
        name: 'SCHEMA_CONFIG'
        value: string(schemaConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create schema
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/schemas" `
        -Body $env:SCHEMA_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $schema = $createResponse | ConvertFrom-Json
      
      # Get schema details
      $schemaDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/schemas/$($schema.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $schemaDetails = $schemaDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        schemaName = $schemaDetails.name
        catalogName = $schemaDetails.catalog_name
        fullName = $schemaDetails.full_name
        schemaId = $schemaDetails.schema_id
        owner = $schemaDetails.owner
        comment = $schemaDetails.comment
        storageRoot = $schemaDetails.storage_root
        createdAt = $schemaDetails.created_at
        updatedAt = $schemaDetails.updated_at
      }
    '''
  }
}

@description('The name of the created schema')
output SchemaName string = schemaCreation.properties.outputs.schemaName

@description('The name of the parent catalog')
output CatalogName string = schemaCreation.properties.outputs.catalogName

@description('The full name of the schema (catalog.schema)')
output FullName string = schemaCreation.properties.outputs.fullName

@description('The unique ID of the schema')
output SchemaId string = schemaCreation.properties.outputs.schemaId

@description('The owner of the schema')
output Owner string = schemaCreation.properties.outputs.owner

@description('The comment for the schema')
output Comment string = schemaCreation.properties.outputs.comment

@description('The storage root of the schema')
output StorageRoot string = schemaCreation.properties.outputs.storageRoot

@description('The creation timestamp of the schema')
output CreatedAt int = int(schemaCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the schema')
output UpdatedAt int = int(schemaCreation.properties.outputs.updatedAt)
