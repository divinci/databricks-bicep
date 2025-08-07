@description('Name of the Delta Live Tables pipeline')
param PipelineName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Pipeline configuration')
param Configuration object = {}

@description('List of libraries for the pipeline')
param Libraries array = []

@description('Target database/schema for the pipeline')
param Target string = ''

@description('Whether the pipeline is continuous')
param Continuous bool = false

@description('Development mode setting')
param Development bool = false

@description('Photon enabled')
param PhotonEnabled bool = true

@description('Pipeline edition')
@allowed(['CORE', 'PRO', 'ADVANCED'])
param Edition string = 'ADVANCED'

@description('Cluster configuration for the pipeline')
param Clusters array = []

var pipelineConfig = {
  name: PipelineName
  configuration: Configuration
  libraries: Libraries
  target: empty(Target) ? null : Target
  continuous: Continuous
  development: Development
  photon: PhotonEnabled
  edition: Edition
  clusters: empty(Clusters) ? null : Clusters
}

resource pipelineCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-pipeline-${uniqueString(PipelineName)}'
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
        name: 'PIPELINE_CONFIG'
        value: string(pipelineConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create pipeline
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/pipelines" `
        -Body $env:PIPELINE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $pipeline = $createResponse | ConvertFrom-Json
      $pipelineId = $pipeline.pipeline_id
      
      # Get pipeline details
      $pipelineDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/pipelines/$pipelineId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $pipelineDetails = $pipelineDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        pipelineId = $pipelineId
        pipelineName = $pipelineDetails.spec.name
        state = $pipelineDetails.state
        creatorUserName = $pipelineDetails.creator_user_name
      }
    '''
  }
}

@description('The ID of the created pipeline')
output PipelineId string = pipelineCreation.properties.outputs.pipelineId

@description('The name of the created pipeline')
output PipelineName string = pipelineCreation.properties.outputs.pipelineName

@description('The current state of the pipeline')
output State string = pipelineCreation.properties.outputs.state

@description('The username of the pipeline creator')
output CreatorUserName string = pipelineCreation.properties.outputs.creatorUserName
