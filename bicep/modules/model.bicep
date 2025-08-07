@description('Name of the Unity Catalog model')
param ModelName string

@description('Catalog name for the model')
param CatalogName string

@description('Schema name for the model')
param SchemaName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the model')
param Comment string = ''

@description('Owner of the model')
param Owner string = ''

@description('Storage location for the model')
param StorageLocation string = ''

var modelConfig = {
  name: ModelName
  catalog_name: CatalogName
  schema_name: SchemaName
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  storage_location: empty(StorageLocation) ? null : StorageLocation
}

resource modelCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-model-${uniqueString(ModelName)}'
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
        name: 'MODEL_CONFIG'
        value: string(modelConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Unity Catalog model
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/models" `
        -Body $env:MODEL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $model = $createResponse | ConvertFrom-Json
      
      # Get model details
      $modelDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/models/$($model.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $modelDetails = $modelDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        modelName = $modelDetails.name
        catalogName = $modelDetails.catalog_name
        schemaName = $modelDetails.schema_name
        fullName = $modelDetails.full_name
        comment = $modelDetails.comment
        owner = $modelDetails.owner
        storageLocation = $modelDetails.storage_location
        createdAt = $modelDetails.created_at
        updatedAt = $modelDetails.updated_at
        modelId = $modelDetails.model_id
      }
    '''
  }
}

@description('The name of the created model')
output ModelName string = modelCreation.properties.outputs.modelName

@description('The catalog name of the model')
output CatalogName string = modelCreation.properties.outputs.catalogName

@description('The schema name of the model')
output SchemaName string = modelCreation.properties.outputs.schemaName

@description('The full name of the model')
output FullName string = modelCreation.properties.outputs.fullName

@description('The comment for the model')
output Comment string = modelCreation.properties.outputs.comment

@description('The owner of the model')
output Owner string = modelCreation.properties.outputs.owner

@description('The storage location of the model')
output StorageLocation string = modelCreation.properties.outputs.storageLocation

@description('The creation timestamp of the model')
output CreatedAt int = int(modelCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the model')
output UpdatedAt int = int(modelCreation.properties.outputs.updatedAt)

@description('The unique ID of the model')
output ModelId string = modelCreation.properties.outputs.modelId
