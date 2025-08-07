@description('Name of the external model')
param ModelName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Catalog name for the external model')
param CatalogName string

@description('Schema name for the external model')
param SchemaName string

@description('Task type of the external model')
@allowed(['llm/v1/chat', 'llm/v1/completions', 'llm/v1/embeddings'])
param Task string

@description('Comment for the external model')
param Comment string = ''

@description('Tags for the external model')
param Tags object = {}

var modelConfig = {
  name: ModelName
  catalog_name: CatalogName
  schema_name: SchemaName
  task: Task
  comment: Comment
  tags: Tags
}

resource externalModelCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-external-model-${uniqueString(ModelName)}'
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
      
      # Create external model
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/external-models" `
        -Body $env:MODEL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $model = $createResponse | ConvertFrom-Json
      
      # Get external model details
      $modelDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/external-models/$($model.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $modelDetails = $modelDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        modelName = $modelDetails.name
        fullName = $modelDetails.full_name
        catalogName = $modelDetails.catalog_name
        schemaName = $modelDetails.schema_name
        task = $modelDetails.task
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

@description('The name of the external model')
output ModelName string = externalModelCreation.properties.outputs.modelName

@description('The full name of the external model')
output FullName string = externalModelCreation.properties.outputs.fullName

@description('The catalog name of the external model')
output CatalogName string = externalModelCreation.properties.outputs.catalogName

@description('The schema name of the external model')
output SchemaName string = externalModelCreation.properties.outputs.schemaName

@description('The task type of the external model')
output Task string = externalModelCreation.properties.outputs.task

@description('The comment of the external model')
output Comment string = externalModelCreation.properties.outputs.comment

@description('The tags of the external model')
output Tags string = externalModelCreation.properties.outputs.tags

@description('The owner of the external model')
output Owner string = externalModelCreation.properties.outputs.owner

@description('The creation timestamp of the external model')
output CreatedAt int = int(externalModelCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the external model')
output UpdatedAt int = int(externalModelCreation.properties.outputs.updatedAt)

@description('The creator of the external model')
output CreatedBy string = externalModelCreation.properties.outputs.createdBy

@description('The last updater of the external model')
output UpdatedBy string = externalModelCreation.properties.outputs.updatedBy
