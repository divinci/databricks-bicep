@description('Name of the SQL alert')
param AlertName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('SQL query ID for the alert')
param QueryId string

@description('Alert condition')
@allowed(['>', '<', '>=', '<=', '==', '!='])
param Condition string

@description('Threshold value for the alert')
param Threshold string

@description('Alert frequency in seconds')
param Rearm int = 0

@description('Custom subject for alert notifications')
param CustomSubject string = ''

@description('Custom body for alert notifications')
param CustomBody string = ''

@description('Parent folder path for the alert')
param Parent string = ''

@description('Options for the alert')
param Options object = {}

var alertConfig = {
  name: AlertName
  query_id: QueryId
  condition: Condition
  threshold: Threshold
  rearm: Rearm == 0 ? null : Rearm
  custom_subject: empty(CustomSubject) ? null : CustomSubject
  custom_body: empty(CustomBody) ? null : CustomBody
  parent: empty(Parent) ? null : Parent
  options: empty(Options) ? {} : Options
}

resource alertCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-alert-${uniqueString(AlertName)}'
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
        name: 'ALERT_CONFIG'
        value: string(alertConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create SQL alert
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/sql/alerts" `
        -Body $env:ALERT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $alert = $createResponse | ConvertFrom-Json
      
      # Get alert details
      $alertDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/sql/alerts/$($alert.id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $alertDetails = $alertDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        alertId = $alertDetails.id
        alertName = $alertDetails.name
        queryId = $alertDetails.query_id
        condition = $alertDetails.condition
        threshold = $alertDetails.threshold
        rearm = $alertDetails.rearm
        customSubject = $alertDetails.custom_subject
        customBody = $alertDetails.custom_body
        parent = $alertDetails.parent
        createdAt = $alertDetails.created_at
        updatedAt = $alertDetails.updated_at
        userId = $alertDetails.user_id
        state = $alertDetails.state
      }
    '''
  }
}

@description('The ID of the created alert')
output AlertId string = alertCreation.properties.outputs.alertId

@description('The name of the alert')
output AlertName string = alertCreation.properties.outputs.alertName

@description('The query ID of the alert')
output QueryId string = alertCreation.properties.outputs.queryId

@description('The condition of the alert')
output Condition string = alertCreation.properties.outputs.condition

@description('The threshold of the alert')
output Threshold string = alertCreation.properties.outputs.threshold

@description('The rearm seconds of the alert')
output Rearm int = int(alertCreation.properties.outputs.rearm)

@description('The custom subject of the alert')
output CustomSubject string = alertCreation.properties.outputs.customSubject

@description('The custom body of the alert')
output CustomBody string = alertCreation.properties.outputs.customBody

@description('The parent folder of the alert')
output Parent string = alertCreation.properties.outputs.parent

@description('The creation timestamp of the alert')
output CreatedAt string = alertCreation.properties.outputs.createdAt

@description('The last updated timestamp of the alert')
output UpdatedAt string = alertCreation.properties.outputs.updatedAt

@description('The user ID of the alert creator')
output UserId int = int(alertCreation.properties.outputs.userId)

@description('The current state of the alert')
output State string = alertCreation.properties.outputs.state
