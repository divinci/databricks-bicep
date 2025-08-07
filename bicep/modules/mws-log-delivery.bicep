@description('Configuration name for the log delivery')
param ConfigName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Account ID for the log delivery')
param AccountId string

@description('Credentials ID for the log delivery')
param CredentialsId string

@description('Storage configuration ID for the log delivery')
param StorageConfigurationId string

@description('Workspace IDs for the log delivery')
param WorkspaceIdsFilter array = []

@description('Log type for the log delivery')
@allowed(['BILLABLE_USAGE', 'AUDIT_LOGS'])
param LogType string

@description('Output format for the log delivery')
@allowed(['CSV', 'JSON'])
param OutputFormat string

var logDeliveryConfig = {
  config_name: ConfigName
  credentials_id: CredentialsId
  storage_configuration_id: StorageConfigurationId
  workspace_ids_filter: WorkspaceIdsFilter
  log_type: LogType
  output_format: OutputFormat
}

resource mwsLogDeliveryCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-log-delivery-${uniqueString(ConfigName)}'
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
        name: 'ACCOUNT_ID'
        value: AccountId
      }
      {
        name: 'LOG_DELIVERY_CONFIG'
        value: string(logDeliveryConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MWS log delivery
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/log-delivery" `
        -Body $env:LOG_DELIVERY_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $logDelivery = $createResponse | ConvertFrom-Json
      
      # Get log delivery details
      $logDeliveryDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/log-delivery/$($logDelivery.config_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $logDeliveryDetails = $logDeliveryDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        configId = $logDeliveryDetails.config_id
        configName = $logDeliveryDetails.config_name
        credentialsId = $logDeliveryDetails.credentials_id
        storageConfigurationId = $logDeliveryDetails.storage_configuration_id
        workspaceIdsFilter = ($logDeliveryDetails.workspace_ids_filter | ConvertTo-Json -Compress)
        logType = $logDeliveryDetails.log_type
        outputFormat = $logDeliveryDetails.output_format
        status = $logDeliveryDetails.status
        accountId = $logDeliveryDetails.account_id
        creationTime = $logDeliveryDetails.creation_time
      }
    '''
  }
}

@description('The configuration ID of the log delivery')
output ConfigId string = mwsLogDeliveryCreation.properties.outputs.configId

@description('The configuration name of the log delivery')
output ConfigName string = mwsLogDeliveryCreation.properties.outputs.configName

@description('The credentials ID of the log delivery')
output CredentialsId string = mwsLogDeliveryCreation.properties.outputs.credentialsId

@description('The storage configuration ID of the log delivery')
output StorageConfigurationId string = mwsLogDeliveryCreation.properties.outputs.storageConfigurationId

@description('The workspace IDs filter of the log delivery')
output WorkspaceIdsFilter string = mwsLogDeliveryCreation.properties.outputs.workspaceIdsFilter

@description('The log type of the log delivery')
output LogType string = mwsLogDeliveryCreation.properties.outputs.logType

@description('The output format of the log delivery')
output OutputFormat string = mwsLogDeliveryCreation.properties.outputs.outputFormat

@description('The status of the log delivery')
output Status string = mwsLogDeliveryCreation.properties.outputs.status

@description('The account ID of the log delivery')
output AccountId string = mwsLogDeliveryCreation.properties.outputs.accountId

@description('The creation time of the log delivery')
output CreationTime int = int(mwsLogDeliveryCreation.properties.outputs.creationTime)
