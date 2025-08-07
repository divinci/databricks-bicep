@description('Name of the SQL query')
param QueryName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('SQL query text')
param Query string

@description('Description of the query')
param Description string = ''

@description('Data source ID for the query')
param DataSourceId string = ''

@description('Tags for the query')
param Tags array = []

@description('Parameters for the query')
param Parameters array = []

@description('Options for the query')
param Options object = {}

var queryConfig = {
  name: QueryName
  query: Query
  description: empty(Description) ? null : Description
  data_source_id: empty(DataSourceId) ? null : DataSourceId
  tags: Tags
  parameters: Parameters
  options: empty(Options) ? {} : Options
}

resource sqlQueryCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-sql-query-${uniqueString(QueryName)}'
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
        name: 'QUERY_CONFIG'
        value: string(queryConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create SQL query
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/preview/sql/queries" `
        -Body $env:QUERY_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $query = $createResponse | ConvertFrom-Json
      $queryId = $query.id
      
      # Get query details
      $queryDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/sql/queries/$queryId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $queryDetails = $queryDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        queryId = $queryDetails.id
        queryName = $queryDetails.name
        description = $queryDetails.description
        query = $queryDetails.query
        dataSourceId = $queryDetails.data_source_id
        createdAt = $queryDetails.created_at
        updatedAt = $queryDetails.updated_at
        userId = $queryDetails.user.id
      }
    '''
  }
}

@description('The ID of the created SQL query')
output QueryId string = sqlQueryCreation.properties.outputs.queryId

@description('The name of the SQL query')
output QueryName string = sqlQueryCreation.properties.outputs.queryName

@description('The description of the query')
output Description string = sqlQueryCreation.properties.outputs.description

@description('The SQL query text')
output Query string = sqlQueryCreation.properties.outputs.query

@description('The data source ID')
output DataSourceId string = sqlQueryCreation.properties.outputs.dataSourceId

@description('The creation timestamp of the query')
output CreatedAt string = sqlQueryCreation.properties.outputs.createdAt

@description('The last update timestamp of the query')
output UpdatedAt string = sqlQueryCreation.properties.outputs.updatedAt

@description('The user ID who created the query')
output UserId int = int(sqlQueryCreation.properties.outputs.userId)
