@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

resource workspaceUrlCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-workspace-url-${uniqueString(WorkspaceUrl)}'
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
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Get workspace information
      $workspaceResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=/" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $workspace = $workspaceResponse | ConvertFrom-Json
      
      # Parse workspace URL components
      $uri = [System.Uri]$env:WORKSPACE_URL
      $workspaceId = $uri.Host.Split('.')[0]
      $region = $uri.Host.Split('.')[1]
      $cloud = if ($uri.Host -match "azuredatabricks") { "azure" } elseif ($uri.Host -match "gcp") { "gcp" } else { "aws" }
      
      $DeploymentScriptOutputs = @{
        workspaceUrl = $env:WORKSPACE_URL
        workspaceId = $workspaceId
        region = $region
        cloud = $cloud
        host = $uri.Host
        scheme = $uri.Scheme
        port = $uri.Port
        isValid = $true
      }
    '''
  }
}

@description('The workspace URL')
output WorkspaceUrl string = workspaceUrlCreation.properties.outputs.workspaceUrl

@description('The workspace ID')
output WorkspaceId string = workspaceUrlCreation.properties.outputs.workspaceId

@description('The workspace region')
output Region string = workspaceUrlCreation.properties.outputs.region

@description('The cloud provider')
output Cloud string = workspaceUrlCreation.properties.outputs.cloud

@description('The workspace host')
output Host string = workspaceUrlCreation.properties.outputs.host

@description('The URL scheme')
output Scheme string = workspaceUrlCreation.properties.outputs.scheme

@description('The URL port')
output Port int = int(workspaceUrlCreation.properties.outputs.port)

@description('Whether the workspace URL is valid')
output IsValid bool = bool(workspaceUrlCreation.properties.outputs.isValid)
