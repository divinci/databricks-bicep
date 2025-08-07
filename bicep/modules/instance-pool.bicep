@description('Name of the Databricks instance pool')
param InstancePoolName string

@description('Node type ID for the instance pool')
param NodeTypeId string

@description('Minimum number of idle instances to maintain')
param MinIdleInstances int = 0

@description('Maximum capacity of the instance pool')
param MaxCapacity int = 10

@description('Idle instance auto-termination time in minutes')
param IdleInstanceAutoTerminationMinutes int = 60

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Custom tags for the instance pool')
param CustomTags object = {}

@description('Preloaded Spark versions for the instance pool')
param PreloadedSparkVersions array = []

@description('Preloaded Docker images for the instance pool')
param PreloadedDockerImages array = []

@description('Whether to enable elastic disk for instances')
param EnableElasticDisk bool = false

@description('Disk specification for instances')
param DiskSpec object = {}

@description('AWS attributes for the instance pool')
param AwsAttributes object = {}

@description('Azure attributes for the instance pool')
param AzureAttributes object = {}

@description('GCP attributes for the instance pool')
param GcpAttributes object = {}

var instancePoolConfig = {
  instance_pool_name: InstancePoolName
  node_type_id: NodeTypeId
  min_idle_instances: MinIdleInstances
  max_capacity: MaxCapacity
  idle_instance_autotermination_minutes: IdleInstanceAutoTerminationMinutes
  custom_tags: CustomTags
  preloaded_spark_versions: PreloadedSparkVersions
  preloaded_docker_images: PreloadedDockerImages
  enable_elastic_disk: EnableElasticDisk
  disk_spec: empty(DiskSpec) ? null : DiskSpec
  aws_attributes: empty(AwsAttributes) ? null : AwsAttributes
  azure_attributes: empty(AzureAttributes) ? null : AzureAttributes
  gcp_attributes: empty(GcpAttributes) ? null : GcpAttributes
}

resource instancePoolCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-instance-pool-${uniqueString(InstancePoolName)}'
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
        name: 'INSTANCE_POOL_CONFIG'
        value: string(instancePoolConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create instance pool
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/instance-pools/create" `
        -Body $env:INSTANCE_POOL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $instancePool = $createResponse | ConvertFrom-Json
      $instancePoolId = $instancePool.instance_pool_id
      
      # Get instance pool details to return full configuration
      $poolDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/instance-pools/get?instance_pool_id=$instancePoolId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $poolDetails = $poolDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        instancePoolId = $instancePoolId
        instancePoolName = $poolDetails.instance_pool_name
        nodeTypeId = $poolDetails.node_type_id
        minIdleInstances = $poolDetails.min_idle_instances
        maxCapacity = $poolDetails.max_capacity
        idleInstanceAutoTerminationMinutes = $poolDetails.idle_instance_autotermination_minutes
        state = $poolDetails.state
      }
    '''
  }
}

@description('The ID of the created Databricks instance pool')
output InstancePoolId string = instancePoolCreation.properties.outputs.instancePoolId

@description('The name of the created Databricks instance pool')
output InstancePoolName string = instancePoolCreation.properties.outputs.instancePoolName

@description('The node type ID used by the instance pool')
output NodeTypeId string = instancePoolCreation.properties.outputs.nodeTypeId

@description('The minimum number of idle instances maintained')
output MinIdleInstances int = int(instancePoolCreation.properties.outputs.minIdleInstances)

@description('The maximum capacity of the instance pool')
output MaxCapacity int = int(instancePoolCreation.properties.outputs.maxCapacity)

@description('The idle instance auto-termination time in minutes')
output IdleInstanceAutoTerminationMinutes int = int(instancePoolCreation.properties.outputs.idleInstanceAutoTerminationMinutes)

@description('The current state of the instance pool')
output State string = instancePoolCreation.properties.outputs.state
