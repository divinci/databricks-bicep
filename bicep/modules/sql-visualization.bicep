@description('Name of the SQL visualization')
param VisualizationName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Query ID for the visualization')
param QueryId string

@description('Visualization type')
@allowed(['CHART', 'COUNTER', 'COHORT', 'BOXPLOT', 'PIVOT', 'FUNNEL', 'SANKEY', 'SUNBURST', 'WORD_CLOUD', 'MAP'])
param Type string

@description('Visualization options configuration')
param Options object

@description('Description of the visualization')
param Description string = ''

var visualizationConfig = {
  name: VisualizationName
  query_id: QueryId
  type: Type
  options: Options
  description: Description
}

resource sqlVisualizationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-sql-visualization-${uniqueString(VisualizationName)}'
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
        name: 'VISUALIZATION_CONFIG'
        value: string(visualizationConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create SQL visualization
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/sql/visualizations" `
        -Body $env:VISUALIZATION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $visualization = $createResponse | ConvertFrom-Json
      
      # Get SQL visualization details
      $visualizationDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/sql/visualizations/$($visualization.id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $visualizationDetails = $visualizationDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        visualizationId = $visualizationDetails.id
        visualizationName = $visualizationDetails.name
        queryId = $visualizationDetails.query_id
        type = $visualizationDetails.type
        options = ($visualizationDetails.options | ConvertTo-Json -Compress)
        description = $visualizationDetails.description
        createdAt = $visualizationDetails.created_at
        updatedAt = $visualizationDetails.updated_at
      }
    '''
  }
}

@description('The visualization ID')
output VisualizationId string = sqlVisualizationCreation.properties.outputs.visualizationId

@description('The visualization name')
output VisualizationName string = sqlVisualizationCreation.properties.outputs.visualizationName

@description('The query ID')
output QueryId string = sqlVisualizationCreation.properties.outputs.queryId

@description('The visualization type')
output Type string = sqlVisualizationCreation.properties.outputs.type

@description('The visualization options')
output Options string = sqlVisualizationCreation.properties.outputs.options

@description('The visualization description')
output Description string = sqlVisualizationCreation.properties.outputs.description

@description('The creation timestamp')
output CreatedAt string = sqlVisualizationCreation.properties.outputs.createdAt

@description('The last updated timestamp')
output UpdatedAt string = sqlVisualizationCreation.properties.outputs.updatedAt
