@description('Name of the model serving endpoint')
param EndpointName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Configuration for the served models')
param Config object

@description('Tags for the endpoint')
param Tags array = []

@description('Rate limits for the endpoint')
param RateLimits array = []

@description('AI Gateway configuration')
param AiGateway object = {}

var endpointConfig = {
  name: EndpointName
  config: Config
  tags: [for tag in Tags: {
    key: tag.key
    value: tag.value
  }]
  rate_limits: RateLimits
  ai_gateway: empty(AiGateway) ? null : AiGateway
}

resource modelServingCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-model-serving-${uniqueString(EndpointName)}'
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
      
      # Create model serving endpoint
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/serving-endpoints" `
        -Body $env:ENDPOINT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $endpoint = $createResponse | ConvertFrom-Json
      $endpointName = $endpoint.name
      
      # Wait for endpoint to be ready (with timeout)
      $maxWaitTime = 300  # 5 minutes
      $waitTime = 0
      $sleepInterval = 10
      
      do {
        Start-Sleep -Seconds $sleepInterval
        $waitTime += $sleepInterval
        
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/serving-endpoints/$endpointName" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $endpointDetails = $statusResponse | ConvertFrom-Json
        $state = $endpointDetails.state.config_update
        
        Write-Host "Endpoint state: $state (waited $waitTime seconds)"
        
        if ($state -eq "UPDATE_SUCCEEDED") {
          break
        }
        
        if ($state -eq "UPDATE_FAILED") {
          throw "Model serving endpoint creation failed"
        }
        
      } while ($waitTime -lt $maxWaitTime)
      
      if ($waitTime -ge $maxWaitTime) {
        Write-Warning "Endpoint creation timed out, but continuing..."
      }
      
      $DeploymentScriptOutputs = @{
        endpointName = $endpointDetails.name
        endpointUrl = $endpointDetails.endpoint_url
        state = $endpointDetails.state.config_update
        creationTimestamp = $endpointDetails.creation_timestamp
        lastUpdatedTimestamp = $endpointDetails.last_updated_timestamp
        creator = $endpointDetails.creator
      }
    '''
  }
}

@description('The name of the created model serving endpoint')
output EndpointName string = modelServingCreation.properties.outputs.endpointName

@description('The URL of the model serving endpoint')
output EndpointUrl string = modelServingCreation.properties.outputs.endpointUrl

@description('The state of the endpoint')
output State string = modelServingCreation.properties.outputs.state

@description('The creation timestamp of the endpoint')
output CreationTimestamp int = int(modelServingCreation.properties.outputs.creationTimestamp)

@description('The last updated timestamp of the endpoint')
output LastUpdatedTimestamp int = int(modelServingCreation.properties.outputs.lastUpdatedTimestamp)

@description('The creator of the endpoint')
output Creator string = modelServingCreation.properties.outputs.creator
