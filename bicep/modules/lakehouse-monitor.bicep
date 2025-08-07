@description('Table name for the lakehouse monitor')
param TableName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Assets directory for the monitor')
param AssetsDir string

@description('Output schema name for the monitor')
param OutputSchemaName string

@description('Inference log for the monitor')
param InferenceLog object = {}

@description('Data classification config for the monitor')
param DataClassificationConfig object = {}

@description('Snapshot for the monitor')
param Snapshot object = {}

@description('Time series configuration for the monitor')
param TimeSeries object = {}

@description('Custom metrics for the monitor')
param CustomMetrics array = []

@description('Notifications configuration for the monitor')
param Notifications object = {}

@description('Schedule configuration for the monitor')
param Schedule object = {}

var monitorConfig = {
  table_name: TableName
  assets_dir: AssetsDir
  output_schema_name: OutputSchemaName
  inference_log: empty(InferenceLog) ? {} : InferenceLog
  data_classification_config: empty(DataClassificationConfig) ? {} : DataClassificationConfig
  snapshot: empty(Snapshot) ? {} : Snapshot
  time_series: empty(TimeSeries) ? {} : TimeSeries
  custom_metrics: CustomMetrics
  notifications: empty(Notifications) ? {} : Notifications
  schedule: empty(Schedule) ? {} : Schedule
}

resource lakehouseMonitorCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-lakehouse-monitor-${uniqueString(TableName)}'
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
        name: 'MONITOR_CONFIG'
        value: string(monitorConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create lakehouse monitor
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/monitors" `
        -Body $env:MONITOR_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $monitor = $createResponse | ConvertFrom-Json
      
      # Get monitor details
      $monitorDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/monitors/$($monitor.table_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $monitorDetails = $monitorDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        tableName = $monitorDetails.table_name
        assetsDir = $monitorDetails.assets_dir
        outputSchemaName = $monitorDetails.output_schema_name
        monitorVersion = $monitorDetails.monitor_version
        status = $monitorDetails.status
        createdBy = $monitorDetails.created_by
        createdTime = $monitorDetails.created_time
        updatedBy = $monitorDetails.updated_by
        updatedTime = $monitorDetails.updated_time
        inferenceLog = ($monitorDetails.inference_log | ConvertTo-Json -Compress)
        dataClassificationConfig = ($monitorDetails.data_classification_config | ConvertTo-Json -Compress)
        snapshot = ($monitorDetails.snapshot | ConvertTo-Json -Compress)
        timeSeries = ($monitorDetails.time_series | ConvertTo-Json -Compress)
        customMetrics = ($monitorDetails.custom_metrics | ConvertTo-Json -Compress)
        notifications = ($monitorDetails.notifications | ConvertTo-Json -Compress)
        schedule = ($monitorDetails.schedule | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The table name of the lakehouse monitor')
output TableName string = lakehouseMonitorCreation.properties.outputs.tableName

@description('The assets directory of the lakehouse monitor')
output AssetsDir string = lakehouseMonitorCreation.properties.outputs.assetsDir

@description('The output schema name of the lakehouse monitor')
output OutputSchemaName string = lakehouseMonitorCreation.properties.outputs.outputSchemaName

@description('The monitor version')
output MonitorVersion string = lakehouseMonitorCreation.properties.outputs.monitorVersion

@description('The status of the lakehouse monitor')
output Status string = lakehouseMonitorCreation.properties.outputs.status

@description('The user who created the lakehouse monitor')
output CreatedBy string = lakehouseMonitorCreation.properties.outputs.createdBy

@description('The creation time of the lakehouse monitor')
output CreatedTime int = int(lakehouseMonitorCreation.properties.outputs.createdTime)

@description('The user who last updated the lakehouse monitor')
output UpdatedBy string = lakehouseMonitorCreation.properties.outputs.updatedBy

@description('The last update time of the lakehouse monitor')
output UpdatedTime int = int(lakehouseMonitorCreation.properties.outputs.updatedTime)

@description('The inference log configuration of the lakehouse monitor')
output InferenceLog string = lakehouseMonitorCreation.properties.outputs.inferenceLog

@description('The data classification config of the lakehouse monitor')
output DataClassificationConfig string = lakehouseMonitorCreation.properties.outputs.dataClassificationConfig

@description('The snapshot configuration of the lakehouse monitor')
output Snapshot string = lakehouseMonitorCreation.properties.outputs.snapshot

@description('The time series configuration of the lakehouse monitor')
output TimeSeries string = lakehouseMonitorCreation.properties.outputs.timeSeries

@description('The custom metrics of the lakehouse monitor')
output CustomMetrics string = lakehouseMonitorCreation.properties.outputs.customMetrics

@description('The notifications configuration of the lakehouse monitor')
output Notifications string = lakehouseMonitorCreation.properties.outputs.notifications

@description('The schedule configuration of the lakehouse monitor')
output Schedule string = lakehouseMonitorCreation.properties.outputs.schedule
