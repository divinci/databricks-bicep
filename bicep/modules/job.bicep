@description('Name of the Databricks job')
param JobName string

@description('Job configuration settings')
param JobSettings object

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Job timeout in seconds')
param TimeoutSeconds int = 3600

@description('Maximum number of concurrent runs')
param MaxConcurrentRuns int = 1

@description('Email notifications configuration')
param EmailNotifications object = {}

@description('Webhook notifications configuration')
param WebhookNotifications object = {}

@description('Job schedule configuration (cron expression)')
param Schedule object = {}

@description('Custom tags for the job')
param Tags object = {}

var jobConfig = {
  name: JobName
  settings: JobSettings
  timeout_seconds: TimeoutSeconds
  max_concurrent_runs: MaxConcurrentRuns
  email_notifications: empty(EmailNotifications) ? null : EmailNotifications
  webhook_notifications: empty(WebhookNotifications) ? null : WebhookNotifications
  schedule: empty(Schedule) ? null : Schedule
  tags: Tags
}

resource jobCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-job-${uniqueString(JobName)}'
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
        name: 'JOB_CONFIG'
        value: string(jobConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create job
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/jobs/create" `
        -Body $env:JOB_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $job = $createResponse | ConvertFrom-Json
      $jobId = $job.job_id
      
      # Get job details to return full configuration
      $jobDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/jobs/get?job_id=$jobId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $jobDetails = $jobDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        jobId = $jobId
        jobName = $jobDetails.settings.name
        createdTime = $jobDetails.created_time
        creatorUserName = $jobDetails.creator_user_name
        timeoutSeconds = $jobDetails.settings.timeout_seconds
        maxConcurrentRuns = $jobDetails.settings.max_concurrent_runs
      }
    '''
  }
}

@description('The ID of the created Databricks job')
output JobId int = int(jobCreation.properties.outputs.jobId)

@description('The name of the created Databricks job')
output JobName string = jobCreation.properties.outputs.jobName

@description('The creation timestamp of the job')
output CreatedTime int = int(jobCreation.properties.outputs.createdTime)

@description('The username of the job creator')
output CreatorUserName string = jobCreation.properties.outputs.creatorUserName

@description('The timeout in seconds for job runs')
output TimeoutSeconds int = int(jobCreation.properties.outputs.timeoutSeconds)

@description('The maximum number of concurrent runs allowed')
output MaxConcurrentRuns int = int(jobCreation.properties.outputs.maxConcurrentRuns)
