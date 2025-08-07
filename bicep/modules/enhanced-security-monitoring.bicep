@description('Workspace ID for enhanced security monitoring')
param WorkspaceId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether enhanced security monitoring is enabled')
param IsEnabled bool = true

@description('Monitoring configuration settings')
param MonitoringConfig object = {}

var esmConfig = {
  workspace_id: WorkspaceId
  is_enabled: IsEnabled
  monitoring_config: MonitoringConfig
}

resource enhancedSecurityMonitoringCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-esm-${uniqueString(WorkspaceId)}'
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
        name: 'ESM_CONFIG'
        value: string(esmConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Update enhanced security monitoring
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/workspace/enhanced-security-monitoring" `
        -Body $env:ESM_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get enhanced security monitoring status
      $esmResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/enhanced-security-monitoring" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $esm = $esmResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        workspaceId = $esm.workspace_id
        isEnabled = $esm.is_enabled
        monitoringConfig = ($esm.monitoring_config | ConvertTo-Json -Compress)
        lastUpdated = $esm.last_updated
      }
    '''
  }
}

@description('The workspace ID')
output WorkspaceId string = enhancedSecurityMonitoringCreation.properties.outputs.workspaceId

@description('Whether enhanced security monitoring is enabled')
output IsEnabled bool = bool(enhancedSecurityMonitoringCreation.properties.outputs.isEnabled)

@description('The monitoring configuration')
output MonitoringConfig string = enhancedSecurityMonitoringCreation.properties.outputs.monitoringConfig

@description('The last updated timestamp')
output LastUpdated int = int(enhancedSecurityMonitoringCreation.properties.outputs.lastUpdated)
