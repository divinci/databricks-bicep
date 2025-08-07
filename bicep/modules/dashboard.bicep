@description('Name of the dashboard')
param DashboardName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Dashboard definition as serialized JSON')
param SerializedDashboard string

@description('Parent folder path for the dashboard')
param Parent string = ''

@description('Tags for the dashboard')
param Tags array = []

var dashboardConfig = {
  display_name: DashboardName
  serialized_dashboard: SerializedDashboard
  parent_path: empty(Parent) ? null : Parent
  warehouse_id: null
}

resource dashboardCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-dashboard-${uniqueString(DashboardName)}'
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
        name: 'DASHBOARD_CONFIG'
        value: string(dashboardConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create dashboard
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/lakeview/dashboards" `
        -Body $env:DASHBOARD_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $dashboard = $createResponse | ConvertFrom-Json
      
      # Get dashboard details
      $dashboardDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/lakeview/dashboards/$($dashboard.dashboard_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $dashboardDetails = $dashboardDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        dashboardId = $dashboardDetails.dashboard_id
        displayName = $dashboardDetails.display_name
        serializedDashboard = $dashboardDetails.serialized_dashboard
        parentPath = $dashboardDetails.parent_path
        warehouseId = $dashboardDetails.warehouse_id
        createdAt = $dashboardDetails.create_time
        updatedAt = $dashboardDetails.update_time
        etag = $dashboardDetails.etag
        path = $dashboardDetails.path
      }
    '''
  }
}

@description('The ID of the created dashboard')
output DashboardId string = dashboardCreation.properties.outputs.dashboardId

@description('The display name of the dashboard')
output DisplayName string = dashboardCreation.properties.outputs.displayName

@description('The serialized dashboard definition')
output SerializedDashboard string = dashboardCreation.properties.outputs.serializedDashboard

@description('The parent path of the dashboard')
output ParentPath string = dashboardCreation.properties.outputs.parentPath

@description('The warehouse ID of the dashboard')
output WarehouseId string = dashboardCreation.properties.outputs.warehouseId

@description('The creation timestamp of the dashboard')
output CreatedAt string = dashboardCreation.properties.outputs.createdAt

@description('The last updated timestamp of the dashboard')
output UpdatedAt string = dashboardCreation.properties.outputs.updatedAt

@description('The etag of the dashboard')
output Etag string = dashboardCreation.properties.outputs.etag

@description('The path of the dashboard')
output Path string = dashboardCreation.properties.outputs.path
