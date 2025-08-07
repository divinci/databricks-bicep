@description('Name of the MLflow experiment')
param ExperimentName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Artifact location for the experiment')
param ArtifactLocation string = ''

@description('Lifecycle stage of the experiment')
@allowed(['active', 'deleted'])
param LifecycleStage string = 'active'

@description('Tags for the experiment')
param Tags object = {}

var experimentConfig = {
  name: ExperimentName
  artifact_location: empty(ArtifactLocation) ? null : ArtifactLocation
  tags: empty(Tags) ? [] : [for key in items(Tags): {
    key: key.key
    value: key.value
  }]
}

resource mlflowExperimentCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mlflow-experiment-${uniqueString(ExperimentName)}'
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
        name: 'EXPERIMENT_CONFIG'
        value: string(experimentConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MLflow experiment
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/mlflow/experiments/create" `
        -Body $env:EXPERIMENT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $experiment = $createResponse | ConvertFrom-Json
      $experimentId = $experiment.experiment_id
      
      # Get experiment details
      $getBody = @{
        experiment_id = $experimentId
      } | ConvertTo-Json
      
      $experimentDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/mlflow/experiments/get?experiment_id=$experimentId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $experimentDetails = $experimentDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        experimentId = $experimentDetails.experiment.experiment_id
        experimentName = $experimentDetails.experiment.name
        artifactLocation = $experimentDetails.experiment.artifact_location
        lifecycleStage = $experimentDetails.experiment.lifecycle_stage
        creationTime = $experimentDetails.experiment.creation_time
        lastUpdateTime = $experimentDetails.experiment.last_update_time
      }
    '''
  }
}

@description('The ID of the created MLflow experiment')
output ExperimentId string = mlflowExperimentCreation.properties.outputs.experimentId

@description('The name of the MLflow experiment')
output ExperimentName string = mlflowExperimentCreation.properties.outputs.experimentName

@description('The artifact location of the experiment')
output ArtifactLocation string = mlflowExperimentCreation.properties.outputs.artifactLocation

@description('The lifecycle stage of the experiment')
output LifecycleStage string = mlflowExperimentCreation.properties.outputs.lifecycleStage

@description('The creation timestamp of the experiment')
output CreationTime int = int(mlflowExperimentCreation.properties.outputs.creationTime)

@description('The last update timestamp of the experiment')
output LastUpdateTime int = int(mlflowExperimentCreation.properties.outputs.lastUpdateTime)
