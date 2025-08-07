@description('Name of the vector search endpoint')
param EndpointName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Endpoint type for the vector search endpoint')
@allowed(['STANDARD', 'DATABRICKS_MANAGED_EMBEDDINGS'])
param EndpointType string

var endpointConfig = {
  name: EndpointName
  endpoint_type: EndpointType
}

resource vectorSearchEndpointCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-vector-search-endpoint-${uniqueString(EndpointName)}'
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
        name: 'ENDPOINT_CONFIG'
        value: string(endpointConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create vector search endpoint
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/vector-search/endpoints" `
        -Body $env:ENDPOINT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $endpoint = $createResponse | ConvertFrom-Json
      
      # Get endpoint details
      $endpointDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/vector-search/endpoints/$($endpoint.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $endpointDetails = $endpointDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        endpointName = $endpointDetails.name
        endpointType = $endpointDetails.endpoint_type
        endpointStatus = ($endpointDetails.endpoint_status | ConvertTo-Json -Compress)
        creationTimestamp = $endpointDetails.creation_timestamp
        lastUpdatedTimestamp = $endpointDetails.last_updated_timestamp
        creator = $endpointDetails.creator
        numIndexes = $endpointDetails.num_indexes
      }
    '''
  }
}

@description('The name of the vector search endpoint')
output EndpointName string = vectorSearchEndpointCreation.properties.outputs.endpointName

@description('The type of the vector search endpoint')
output EndpointType string = vectorSearchEndpointCreation.properties.outputs.endpointType

@description('The status of the vector search endpoint')
output EndpointStatus string = vectorSearchEndpointCreation.properties.outputs.endpointStatus

@description('The creation timestamp of the vector search endpoint')
output CreationTimestamp int = int(vectorSearchEndpointCreation.properties.outputs.creationTimestamp)

@description('The last updated timestamp of the vector search endpoint')
output LastUpdatedTimestamp int = int(vectorSearchEndpointCreation.properties.outputs.lastUpdatedTimestamp)

@description('The creator of the vector search endpoint')
output Creator string = vectorSearchEndpointCreation.properties.outputs.creator

@description('The number of indexes in the vector search endpoint')
output NumIndexes int = int(vectorSearchEndpointCreation.properties.outputs.numIndexes)
