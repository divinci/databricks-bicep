@description('Name of the notification destination')
param DestinationName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Type of notification destination')
@allowed(['email', 'slack', 'pagerduty', 'webhook'])
param DestinationType string

@description('Configuration for the notification destination')
param Config object

var destinationConfig = {
  display_name: DestinationName
  destination_type: DestinationType
  config: Config
}

resource notificationDestinationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-notification-destination-${uniqueString(DestinationName)}'
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
        name: 'DESTINATION_CONFIG'
        value: string(destinationConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create notification destination
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/sql/config/notification-destinations" `
        -Body $env:DESTINATION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $destination = $createResponse | ConvertFrom-Json
      
      # Get destination details
      $destinationDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/sql/config/notification-destinations/$($destination.id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $destinationDetails = $destinationDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        destinationId = $destinationDetails.id
        displayName = $destinationDetails.display_name
        destinationType = $destinationDetails.destination_type
        config = ($destinationDetails.config | ConvertTo-Json -Compress)
        createdBy = $destinationDetails.created_by
        createdAt = $destinationDetails.created_at
        updatedBy = $destinationDetails.updated_by
        updatedAt = $destinationDetails.updated_at
      }
    '''
  }
}

@description('The ID of the created notification destination')
output DestinationId string = notificationDestinationCreation.properties.outputs.destinationId

@description('The display name of the notification destination')
output DisplayName string = notificationDestinationCreation.properties.outputs.displayName

@description('The type of the notification destination')
output DestinationType string = notificationDestinationCreation.properties.outputs.destinationType

@description('The configuration of the notification destination')
output Config string = notificationDestinationCreation.properties.outputs.config

@description('The user who created the notification destination')
output CreatedBy string = notificationDestinationCreation.properties.outputs.createdBy

@description('The creation timestamp of the notification destination')
output CreatedAt string = notificationDestinationCreation.properties.outputs.createdAt

@description('The user who last updated the notification destination')
output UpdatedBy string = notificationDestinationCreation.properties.outputs.updatedBy

@description('The last update timestamp of the notification destination')
output UpdatedAt string = notificationDestinationCreation.properties.outputs.updatedAt
