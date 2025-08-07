@description('Cluster ID to install the library on')
param ClusterId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Library specification')
param Library object

var libraryConfig = {
  cluster_id: ClusterId
  libraries: [Library]
}

resource clusterLibraryCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-cluster-library-${uniqueString(ClusterId, string(Library))}'
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
        name: 'LIBRARY_CONFIG'
        value: string(libraryConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Install library on cluster
      $installResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/libraries/install" `
        -Body $env:LIBRARY_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $libraryConfigObj = $env:LIBRARY_CONFIG | ConvertFrom-Json
      
      # Get library status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/libraries/cluster-status?cluster_id=$($libraryConfigObj.cluster_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        clusterId = $status.cluster_id
        libraryStatuses = ($status.library_statuses | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The cluster ID')
output ClusterId string = clusterLibraryCreation.properties.outputs.clusterId

@description('The library statuses')
output LibraryStatuses string = clusterLibraryCreation.properties.outputs.libraryStatuses
