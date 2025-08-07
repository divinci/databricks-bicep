@description('Name of the online table')
param TableName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Spec for the online table')
param Spec object

var onlineTableConfig = {
  name: TableName
  spec: Spec
}

resource onlineTableCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-online-table-${uniqueString(TableName)}'
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
        name: 'ONLINE_TABLE_CONFIG'
        value: string(onlineTableConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create online table
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/serving-endpoints/online-tables" `
        -Body $env:ONLINE_TABLE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $onlineTable = $createResponse | ConvertFrom-Json
      
      # Get online table details
      $onlineTableDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/serving-endpoints/online-tables/$($onlineTable.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $onlineTableDetails = $onlineTableDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        tableName = $onlineTableDetails.name
        spec = ($onlineTableDetails.spec | ConvertTo-Json -Compress)
        status = ($onlineTableDetails.status | ConvertTo-Json -Compress)
        tableServingUrl = $onlineTableDetails.table_serving_url
      }
    '''
  }
}

@description('The name of the created online table')
output TableName string = onlineTableCreation.properties.outputs.tableName

@description('The spec of the online table')
output Spec string = onlineTableCreation.properties.outputs.spec

@description('The status of the online table')
output Status string = onlineTableCreation.properties.outputs.status

@description('The serving URL of the online table')
output TableServingUrl string = onlineTableCreation.properties.outputs.tableServingUrl
