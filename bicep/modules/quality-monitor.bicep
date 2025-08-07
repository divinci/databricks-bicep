@description('Table name for the quality monitor')
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

resource qualityMonitorCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-quality-monitor-${uniqueString(TableName)}'
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
      
      # Create quality monitor
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/quality-monitors" `
        -Body $env:MONITOR_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $monitor = $createResponse | ConvertFrom-Json
      
      # Get monitor details
      $monitorDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/quality-monitors/$($monitor.table_name)" `
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

@description('The table name of the quality monitor')
output TableName string = qualityMonitorCreation.properties.outputs.tableName

@description('The assets directory of the quality monitor')
output AssetsDir string = qualityMonitorCreation.properties.outputs.assetsDir

@description('The output schema name of the quality monitor')
output OutputSchemaName string = qualityMonitorCreation.properties.outputs.outputSchemaName

@description('The monitor version')
output MonitorVersion string = qualityMonitorCreation.properties.outputs.monitorVersion

@description('The status of the quality monitor')
output Status string = qualityMonitorCreation.properties.outputs.status

@description('The user who created the quality monitor')
output CreatedBy string = qualityMonitorCreation.properties.outputs.createdBy

@description('The creation time of the quality monitor')
output CreatedTime int = int(qualityMonitorCreation.properties.outputs.createdTime)

@description('The user who last updated the quality monitor')
output UpdatedBy string = qualityMonitorCreation.properties.outputs.updatedBy

@description('The last update time of the quality monitor')
output UpdatedTime int = int(qualityMonitorCreation.properties.outputs.updatedTime)

@description('The inference log configuration of the quality monitor')
output InferenceLog string = qualityMonitorCreation.properties.outputs.inferenceLog

@description('The data classification config of the quality monitor')
output DataClassificationConfig string = qualityMonitorCreation.properties.outputs.dataClassificationConfig

@description('The snapshot configuration of the quality monitor')
output Snapshot string = qualityMonitorCreation.properties.outputs.snapshot

@description('The time series configuration of the quality monitor')
output TimeSeries string = qualityMonitorCreation.properties.outputs.timeSeries

@description('The custom metrics of the quality monitor')
output CustomMetrics string = qualityMonitorCreation.properties.outputs.customMetrics

@description('The notifications configuration of the quality monitor')
output Notifications string = qualityMonitorCreation.properties.outputs.notifications

@description('The schedule configuration of the quality monitor')
output Schedule string = qualityMonitorCreation.properties.outputs.schedule
