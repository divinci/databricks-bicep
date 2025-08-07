@description('Name of the registered model')
param ModelName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Catalog name for the registered model')
param CatalogName string

@description('Schema name for the registered model')
param SchemaName string

@description('Comment for the registered model')
param Comment string = ''

@description('Tags for the registered model')
param Tags object = {}

var modelConfig = {
  name: ModelName
  catalog_name: CatalogName
  schema_name: SchemaName
  comment: Comment
  tags: Tags
}

resource registeredModelCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-registered-model-${uniqueString(ModelName)}'
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
      
      # Create registered model
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/models" `
        -Body $env:MODEL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $model = $createResponse | ConvertFrom-Json
      
      # Get registered model details
      $modelDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/models/$($model.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $modelDetails = $modelDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        modelName = $modelDetails.name
        fullName = $modelDetails.full_name
        catalogName = $modelDetails.catalog_name
        schemaName = $modelDetails.schema_name
        comment = $modelDetails.comment
        tags = ($modelDetails.tags | ConvertTo-Json -Compress)
        owner = $modelDetails.owner
        createdAt = $modelDetails.created_at
        updatedAt = $modelDetails.updated_at
        createdBy = $modelDetails.created_by
        updatedBy = $modelDetails.updated_by
      }
    '''
  }
}

@description('The name of the registered model')
output ModelName string = registeredModelCreation.properties.outputs.modelName

@description('The full name of the registered model')
output FullName string = registeredModelCreation.properties.outputs.fullName

@description('The catalog name of the registered model')
output CatalogName string = registeredModelCreation.properties.outputs.catalogName

@description('The schema name of the registered model')
output SchemaName string = registeredModelCreation.properties.outputs.schemaName

@description('The comment of the registered model')
output Comment string = registeredModelCreation.properties.outputs.comment

@description('The tags of the registered model')
output Tags string = registeredModelCreation.properties.outputs.tags

@description('The owner of the registered model')
output Owner string = registeredModelCreation.properties.outputs.owner

@description('The creation timestamp of the registered model')
output CreatedAt int = int(registeredModelCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the registered model')
output UpdatedAt int = int(registeredModelCreation.properties.outputs.updatedAt)

@description('The creator of the registered model')
output CreatedBy string = registeredModelCreation.properties.outputs.createdBy

@description('The last updater of the registered model')
output UpdatedBy string = registeredModelCreation.properties.outputs.updatedBy
