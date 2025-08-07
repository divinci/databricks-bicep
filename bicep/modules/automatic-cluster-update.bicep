@description('Workspace ID for automatic cluster update')
param WorkspaceId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether automatic cluster update is enabled')
param IsEnabled bool = true

@description('Update schedule configuration')
param UpdateSchedule object = {}

@description('Maintenance window configuration')
param MaintenanceWindow object = {}

var updateConfig = {
  workspace_id: WorkspaceId
  is_enabled: IsEnabled
  update_schedule: UpdateSchedule
  maintenance_window: MaintenanceWindow
}

resource automaticClusterUpdateCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-auto-update-${uniqueString(WorkspaceId)}'
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
        name: 'UPDATE_CONFIG'
        value: string(updateConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Update automatic cluster update settings
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/clusters/automatic-update" `
        -Body $env:UPDATE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get automatic cluster update settings
      $settingsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/clusters/automatic-update" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $settings = $settingsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        workspaceId = $settings.workspace_id
        isEnabled = $settings.is_enabled
        updateSchedule = ($settings.update_schedule | ConvertTo-Json -Compress)
        maintenanceWindow = ($settings.maintenance_window | ConvertTo-Json -Compress)
        lastUpdated = $settings.last_updated
      }
    '''
  }
}

@description('The workspace ID')
output WorkspaceId string = automaticClusterUpdateCreation.properties.outputs.workspaceId

@description('Whether automatic cluster update is enabled')
output IsEnabled bool = bool(automaticClusterUpdateCreation.properties.outputs.isEnabled)

@description('The update schedule configuration')
output UpdateSchedule string = automaticClusterUpdateCreation.properties.outputs.updateSchedule

@description('The maintenance window configuration')
output MaintenanceWindow string = automaticClusterUpdateCreation.properties.outputs.maintenanceWindow

@description('The last updated timestamp')
output LastUpdated int = int(automaticClusterUpdateCreation.properties.outputs.lastUpdated)
