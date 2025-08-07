@description('Name of the Unity Catalog table')
param TableName string

@description('Catalog name for the table')
param CatalogName string

@description('Schema name for the table')
param SchemaName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Table type')
@allowed(['MANAGED', 'EXTERNAL', 'VIEW'])
param TableType string

@description('Data source format for the table')
@allowed(['DELTA', 'CSV', 'JSON', 'AVRO', 'PARQUET', 'ORC', 'TEXT'])
param DataSourceFormat string = 'DELTA'

@description('Storage location for external tables')
param StorageLocation string = ''

@description('View definition for view tables')
param ViewDefinition string = ''

@description('Comment for the table')
param Comment string = ''

@description('Owner of the table')
param Owner string = ''

@description('Properties for the table')
param Properties object = {}

@description('Column definitions for the table')
param Columns array = []

var tableConfig = {
  name: TableName
  catalog_name: CatalogName
  schema_name: SchemaName
  table_type: TableType
  data_source_format: DataSourceFormat
  storage_location: empty(StorageLocation) ? null : StorageLocation
  view_definition: empty(ViewDefinition) ? null : ViewDefinition
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  properties: empty(Properties) ? {} : Properties
  columns: Columns
}

resource tableCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-table-${uniqueString(TableName)}'
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
        name: 'TABLE_CONFIG'
        value: string(tableConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Unity Catalog table
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/tables" `
        -Body $env:TABLE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $table = $createResponse | ConvertFrom-Json
      
      # Get table details
      $tableDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/tables/$($table.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $tableDetails = $tableDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        tableName = $tableDetails.name
        catalogName = $tableDetails.catalog_name
        schemaName = $tableDetails.schema_name
        fullName = $tableDetails.full_name
        tableType = $tableDetails.table_type
        dataSourceFormat = $tableDetails.data_source_format
        storageLocation = $tableDetails.storage_location
        viewDefinition = $tableDetails.view_definition
        comment = $tableDetails.comment
        owner = $tableDetails.owner
        createdAt = $tableDetails.created_at
        updatedAt = $tableDetails.updated_at
        tableId = $tableDetails.table_id
      }
    '''
  }
}

@description('The name of the created table')
output TableName string = tableCreation.properties.outputs.tableName

@description('The catalog name of the table')
output CatalogName string = tableCreation.properties.outputs.catalogName

@description('The schema name of the table')
output SchemaName string = tableCreation.properties.outputs.schemaName

@description('The full name of the table')
output FullName string = tableCreation.properties.outputs.fullName

@description('The type of the table')
output TableType string = tableCreation.properties.outputs.tableType

@description('The data source format of the table')
output DataSourceFormat string = tableCreation.properties.outputs.dataSourceFormat

@description('The storage location of the table')
output StorageLocation string = tableCreation.properties.outputs.storageLocation

@description('The view definition of the table')
output ViewDefinition string = tableCreation.properties.outputs.viewDefinition

@description('The comment for the table')
output Comment string = tableCreation.properties.outputs.comment

@description('The owner of the table')
output Owner string = tableCreation.properties.outputs.owner

@description('The creation timestamp of the table')
output CreatedAt int = int(tableCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the table')
output UpdatedAt int = int(tableCreation.properties.outputs.updatedAt)

@description('The unique ID of the table')
output TableId string = tableCreation.properties.outputs.tableId
