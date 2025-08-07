@description('Model name for the version')
param ModelName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Catalog name for the model version')
param CatalogName string

@description('Schema name for the model version')
param SchemaName string

@description('Version number')
param Version int

@description('Source URI for the model version')
param Source string

@description('Run ID associated with the model version')
param RunId string = ''

@description('Comment for the model version')
param Comment string = ''

@description('Tags for the model version')
param Tags object = {}

var versionConfig = {
  catalog_name: CatalogName
  schema_name: SchemaName
  model_name: ModelName
  version: Version
  source: Source
  run_id: RunId
  comment: Comment
  tags: Tags
}

resource modelVersionCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-model-version-${uniqueString(ModelName, string(Version))}'
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
        name: 'VERSION_CONFIG'
        value: string(versionConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $versionConfigObj = $env:VERSION_CONFIG | ConvertFrom-Json
      $fullModelName = "$($versionConfigObj.catalog_name).$($versionConfigObj.schema_name).$($versionConfigObj.model_name)"
      
      # Create model version
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/models/$fullModelName/versions" `
        -Body $env:VERSION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $version = $createResponse | ConvertFrom-Json
      
      # Get model version details
      $versionDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/models/$fullModelName/versions/$($version.version)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $versionDetails = $versionDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        modelName = $versionDetails.model_name
        fullName = $versionDetails.full_name
        catalogName = $versionDetails.catalog_name
        schemaName = $versionDetails.schema_name
        version = $versionDetails.version
        source = $versionDetails.source
        runId = $versionDetails.run_id
        comment = $versionDetails.comment
        tags = ($versionDetails.tags | ConvertTo-Json -Compress)
        status = $versionDetails.status
        createdAt = $versionDetails.created_at
        updatedAt = $versionDetails.updated_at
        createdBy = $versionDetails.created_by
        updatedBy = $versionDetails.updated_by
      }
    '''
  }
}

@description('The name of the model')
output ModelName string = modelVersionCreation.properties.outputs.modelName

@description('The full name of the model version')
output FullName string = modelVersionCreation.properties.outputs.fullName

@description('The catalog name of the model version')
output CatalogName string = modelVersionCreation.properties.outputs.catalogName

@description('The schema name of the model version')
output SchemaName string = modelVersionCreation.properties.outputs.schemaName

@description('The version number')
output Version int = int(modelVersionCreation.properties.outputs.version)

@description('The source URI of the model version')
output Source string = modelVersionCreation.properties.outputs.source

@description('The run ID associated with the model version')
output RunId string = modelVersionCreation.properties.outputs.runId

@description('The comment of the model version')
output Comment string = modelVersionCreation.properties.outputs.comment

@description('The tags of the model version')
output Tags string = modelVersionCreation.properties.outputs.tags

@description('The status of the model version')
output Status string = modelVersionCreation.properties.outputs.status

@description('The creation timestamp of the model version')
output CreatedAt int = int(modelVersionCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the model version')
output UpdatedAt int = int(modelVersionCreation.properties.outputs.updatedAt)

@description('The creator of the model version')
output CreatedBy string = modelVersionCreation.properties.outputs.createdBy

@description('The last updater of the model version')
output UpdatedBy string = modelVersionCreation.properties.outputs.updatedBy
