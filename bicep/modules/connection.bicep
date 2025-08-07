@description('Name of the connection')
param ConnectionName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Connection type')
@allowed(['MYSQL', 'POSTGRESQL', 'REDSHIFT', 'SNOWFLAKE', 'SQLSERVER', 'DATABRICKS', 'BIGQUERY'])
param ConnectionType string

@description('Comment for the connection')
param Comment string = ''

@description('Options for the connection')
param Options object

@description('Properties for the connection')
param Properties object = {}

@description('Owner of the connection')
param Owner string = ''

@description('Whether the connection is read-only')
param ReadOnly bool = false

var connectionConfig = {
  name: ConnectionName
  connection_type: ConnectionType
  comment: empty(Comment) ? null : Comment
  options: Options
  properties: empty(Properties) ? {} : Properties
  owner: empty(Owner) ? null : Owner
  read_only: ReadOnly
}

resource connectionCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-connection-${uniqueString(ConnectionName)}'
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
        name: 'CONNECTION_CONFIG'
        value: string(connectionConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create connection
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/connections" `
        -Body $env:CONNECTION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $connection = $createResponse | ConvertFrom-Json
      
      # Get connection details
      $connectionDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/connections/$($connection.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $connectionDetails = $connectionDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        connectionName = $connectionDetails.name
        connectionType = $connectionDetails.connection_type
        comment = $connectionDetails.comment
        owner = $connectionDetails.owner
        readOnly = $connectionDetails.read_only
        createdAt = $connectionDetails.created_at
        updatedAt = $connectionDetails.updated_at
        connectionId = $connectionDetails.connection_id
      }
    '''
  }
}

@description('The name of the created connection')
output ConnectionName string = connectionCreation.properties.outputs.connectionName

@description('The type of the connection')
output ConnectionType string = connectionCreation.properties.outputs.connectionType

@description('The comment for the connection')
output Comment string = connectionCreation.properties.outputs.comment

@description('The owner of the connection')
output Owner string = connectionCreation.properties.outputs.owner

@description('Whether the connection is read-only')
output ReadOnly bool = bool(connectionCreation.properties.outputs.readOnly)

@description('The creation timestamp of the connection')
output CreatedAt int = int(connectionCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the connection')
output UpdatedAt int = int(connectionCreation.properties.outputs.updatedAt)

@description('The unique ID of the connection')
output ConnectionId string = connectionCreation.properties.outputs.connectionId
