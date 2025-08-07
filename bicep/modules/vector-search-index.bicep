@description('Name of the vector search index')
param IndexName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Endpoint name for the vector search index')
param EndpointName string

@description('Primary key for the vector search index')
param PrimaryKey string

@description('Index type for the vector search index')
@allowed(['DELTA_SYNC', 'DIRECT_ACCESS'])
param IndexType string

@description('Delta sync index specification')
param DeltaSyncIndexSpec object = {}

@description('Direct access index specification')
param DirectAccessIndexSpec object = {}

var indexConfig = {
  name: IndexName
  endpoint_name: EndpointName
  primary_key: PrimaryKey
  index_type: IndexType
  delta_sync_index_spec: empty(DeltaSyncIndexSpec) ? {} : DeltaSyncIndexSpec
  direct_access_index_spec: empty(DirectAccessIndexSpec) ? {} : DirectAccessIndexSpec
}

resource vectorSearchIndexCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-vector-search-index-${uniqueString(IndexName)}'
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
        name: 'INDEX_CONFIG'
        value: string(indexConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create vector search index
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/vector-search/indexes" `
        -Body $env:INDEX_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $index = $createResponse | ConvertFrom-Json
      
      # Get index details
      $indexDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/vector-search/indexes/$($index.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $indexDetails = $indexDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        indexName = $indexDetails.name
        endpointName = $indexDetails.endpoint_name
        primaryKey = $indexDetails.primary_key
        indexType = $indexDetails.index_type
        indexStatus = ($indexDetails.status | ConvertTo-Json -Compress)
        creationTimestamp = $indexDetails.creation_timestamp
        creator = $indexDetails.creator
        deltaSyncIndexSpec = ($indexDetails.delta_sync_index_spec | ConvertTo-Json -Compress)
        directAccessIndexSpec = ($indexDetails.direct_access_index_spec | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The name of the vector search index')
output IndexName string = vectorSearchIndexCreation.properties.outputs.indexName

@description('The endpoint name of the vector search index')
output EndpointName string = vectorSearchIndexCreation.properties.outputs.endpointName

@description('The primary key of the vector search index')
output PrimaryKey string = vectorSearchIndexCreation.properties.outputs.primaryKey

@description('The type of the vector search index')
output IndexType string = vectorSearchIndexCreation.properties.outputs.indexType

@description('The status of the vector search index')
output IndexStatus string = vectorSearchIndexCreation.properties.outputs.indexStatus

@description('The creation timestamp of the vector search index')
output CreationTimestamp int = int(vectorSearchIndexCreation.properties.outputs.creationTimestamp)

@description('The creator of the vector search index')
output Creator string = vectorSearchIndexCreation.properties.outputs.creator

@description('The delta sync index specification')
output DeltaSyncIndexSpec string = vectorSearchIndexCreation.properties.outputs.deltaSyncIndexSpec

@description('The direct access index specification')
output DirectAccessIndexSpec string = vectorSearchIndexCreation.properties.outputs.directAccessIndexSpec
