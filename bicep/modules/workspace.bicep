@description('Name of the Databricks workspace configuration')
param WorkspaceName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Workspace configuration settings')
param WorkspaceConf object = {}

@description('Enable automatic cluster termination')
param EnableAutomaticClusterTermination bool = true

@description('Maximum token lifetime in seconds')
param MaxTokenLifetimeSeconds int = 7776000

@description('Maximum number of clusters per user')
param MaxClustersPerUser int = 0

var workspaceConfig = {
  enableAutomaticClusterTermination: string(EnableAutomaticClusterTermination)
  maxTokenLifetimeSeconds: string(MaxTokenLifetimeSeconds)
  maxClustersPerUser: MaxClustersPerUser == 0 ? null : string(MaxClustersPerUser)
}

// Merge with custom workspace configuration
var finalWorkspaceConf = union(workspaceConfig, WorkspaceConf)

resource workspaceConfiguration 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-databricks-workspace-${uniqueString(WorkspaceName)}'
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
        name: 'WORKSPACE_CONF'
        value: string(finalWorkspaceConf)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $workspaceConf = $env:WORKSPACE_CONF | ConvertFrom-Json
      
      # Update workspace configuration
      foreach ($key in $workspaceConf.PSObject.Properties.Name) {
        $value = $workspaceConf.$key
        if ($null -ne $value) {
          $configBody = @{
            $key = $value
          } | ConvertTo-Json -Depth 10
          
          Write-Host "Setting workspace configuration: $key = $value"
          
          $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
            -Method "PATCH" `
            -UrlPath "/api/2.0/workspace-conf" `
            -Body $configBody `
            -DatabricksToken $secureToken `
            -WorkspaceUrl $env:WORKSPACE_URL
        }
      }
      
      # Get current workspace configuration
      $currentConfResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace-conf" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $currentConf = $currentConfResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        workspaceName = $env:WORKSPACE_NAME
        enableAutomaticClusterTermination = $currentConf.enableAutomaticClusterTermination
        maxTokenLifetimeSeconds = $currentConf.maxTokenLifetimeSeconds
        maxClustersPerUser = $currentConf.maxClustersPerUser
      }
    '''
  }
}

@description('The name of the configured workspace')
output WorkspaceName string = WorkspaceName

@description('Whether automatic cluster termination is enabled')
output EnableAutomaticClusterTermination string = workspaceConfiguration.properties.outputs.enableAutomaticClusterTermination

@description('Maximum token lifetime in seconds')
output MaxTokenLifetimeSeconds string = workspaceConfiguration.properties.outputs.maxTokenLifetimeSeconds

@description('Maximum number of clusters per user')
output MaxClustersPerUser string = workspaceConfiguration.properties.outputs.maxClustersPerUser
