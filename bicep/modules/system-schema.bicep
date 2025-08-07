@description('System schema name')
param SchemaName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('State of the system schema')
@allowed(['ENABLE', 'DISABLE'])
param State string

var schemaConfig = {
  schema_name: SchemaName
  state: State
}

resource systemSchemaCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-system-schema-${uniqueString(SchemaName)}'
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
      
      $schemaConfigObj = $env:SCHEMA_CONFIG | ConvertFrom-Json
      
      # Update system schema state
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.1/unity-catalog/system-schemas/$($schemaConfigObj.schema_name)" `
        -Body $env:SCHEMA_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get system schema details
      $schemaResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/system-schemas/$($schemaConfigObj.schema_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $schema = $schemaResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        schemaName = $schema.schema_name
        state = $schema.state
        metastoreId = $schema.metastore_id
      }
    '''
  }
}

@description('The system schema name')
output SchemaName string = systemSchemaCreation.properties.outputs.schemaName

@description('The state of the system schema')
output State string = systemSchemaCreation.properties.outputs.state

@description('The metastore ID')
output MetastoreId string = systemSchemaCreation.properties.outputs.metastoreId
