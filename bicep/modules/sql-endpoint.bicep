@description('Name of the SQL endpoint')
param EndpointName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Cluster size for the SQL endpoint')
@allowed(['2X-Small', 'X-Small', 'Small', 'Medium', 'Large', 'X-Large', '2X-Large', '3X-Large', '4X-Large'])
param ClusterSize string = 'Small'

@description('Minimum number of clusters')
param MinNumClusters int = 1

@description('Maximum number of clusters')
param MaxNumClusters int = 1

@description('Auto stop minutes')
param AutoStopMins int = 120

@description('Enable auto stop')
param EnableAutoStop bool = true

@description('Enable photon')
param EnablePhoton bool = true

@description('Spot instance policy')
@allowed(['COST_OPTIMIZED', 'RELIABILITY_OPTIMIZED', 'POLICY_UNSPECIFIED'])
param SpotInstancePolicy string = 'COST_OPTIMIZED'

@description('Channel for the SQL endpoint')
param Channel object = {
  name: 'CHANNEL_NAME_CURRENT'
}

var endpointConfig = {
  name: EndpointName
  cluster_size: ClusterSize
  min_num_clusters: MinNumClusters
  max_num_clusters: MaxNumClusters
  auto_stop_mins: EnableAutoStop ? AutoStopMins : null
  enable_photon: EnablePhoton
  spot_instance_policy: SpotInstancePolicy
  channel: Channel
}

resource sqlEndpointCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-sql-endpoint-${uniqueString(EndpointName)}'
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
      
      # Create SQL endpoint
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/sql/warehouses" `
        -Body $env:ENDPOINT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $endpoint = $createResponse | ConvertFrom-Json
      $endpointId = $endpoint.id
      
      # Wait for endpoint to be ready
      $maxAttempts = 30
      $attempt = 0
      
      do {
        Start-Sleep -Seconds 30
        $attempt++
        
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/sql/warehouses/$endpointId" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $status = ($statusResponse | ConvertFrom-Json).state
        Write-Host "SQL endpoint status: $status (attempt $attempt/$maxAttempts)"
        
        if ($status -eq "RUNNING") {
          break
        }
        elseif ($status -in @("STOPPED", "DELETED")) {
          throw "SQL endpoint creation failed with status: $status"
        }
      } while ($attempt -lt $maxAttempts)
      
      if ($attempt -ge $maxAttempts) {
        throw "SQL endpoint creation timed out after $maxAttempts attempts"
      }
      
      $DeploymentScriptOutputs = @{
        endpointId = $endpointId
        endpointName = $endpoint.name
        state = $status
        clusterSize = $endpoint.cluster_size
        jdbcUrl = $endpoint.jdbc_url
      }
    '''
  }
}

@description('The ID of the created SQL endpoint')
output EndpointId string = sqlEndpointCreation.properties.outputs.endpointId

@description('The name of the created SQL endpoint')
output EndpointName string = sqlEndpointCreation.properties.outputs.endpointName

@description('The current state of the SQL endpoint')
output State string = sqlEndpointCreation.properties.outputs.state

@description('The cluster size of the SQL endpoint')
output ClusterSize string = sqlEndpointCreation.properties.outputs.clusterSize

@description('The JDBC URL for connecting to the SQL endpoint')
output JdbcUrl string = sqlEndpointCreation.properties.outputs.jdbcUrl
