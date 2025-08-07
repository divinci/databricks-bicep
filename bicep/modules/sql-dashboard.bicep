@description('Name of the SQL dashboard')
param DashboardName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Tags for the dashboard')
param Tags array = []

@description('Whether the dashboard is archived')
param IsArchived bool = false

@description('Whether the dashboard is draft')
param IsDraft bool = false

@description('Parent folder for the dashboard')
param Parent string = ''

var dashboardConfig = {
  name: DashboardName
  tags: Tags
  is_archived: IsArchived
  is_draft: IsDraft
  parent: empty(Parent) ? null : Parent
}

resource sqlDashboardCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-sql-dashboard-${uniqueString(DashboardName)}'
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
      
      # Create SQL dashboard
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/preview/sql/dashboards" `
        -Body $env:DASHBOARD_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $dashboard = $createResponse | ConvertFrom-Json
      $dashboardId = $dashboard.id
      
      # Get dashboard details
      $dashboardDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/sql/dashboards/$dashboardId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $dashboardDetails = $dashboardDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        dashboardId = $dashboardDetails.id
        dashboardName = $dashboardDetails.name
        slug = $dashboardDetails.slug
        isArchived = $dashboardDetails.is_archived
        isDraft = $dashboardDetails.is_draft
        createdAt = $dashboardDetails.created_at
        updatedAt = $dashboardDetails.updated_at
        userId = $dashboardDetails.user.id
      }
    '''
  }
}

@description('The ID of the created SQL dashboard')
output DashboardId string = sqlDashboardCreation.properties.outputs.dashboardId

@description('The name of the SQL dashboard')
output DashboardName string = sqlDashboardCreation.properties.outputs.dashboardName

@description('The slug of the dashboard')
output Slug string = sqlDashboardCreation.properties.outputs.slug

@description('Whether the dashboard is archived')
output IsArchived bool = bool(sqlDashboardCreation.properties.outputs.isArchived)

@description('Whether the dashboard is draft')
output IsDraft bool = bool(sqlDashboardCreation.properties.outputs.isDraft)

@description('The creation timestamp of the dashboard')
output CreatedAt string = sqlDashboardCreation.properties.outputs.createdAt

@description('The last update timestamp of the dashboard')
output UpdatedAt string = sqlDashboardCreation.properties.outputs.updatedAt

@description('The user ID who created the dashboard')
output UserId int = int(sqlDashboardCreation.properties.outputs.userId)
