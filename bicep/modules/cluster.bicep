@description('Name of the Databricks cluster')
param ClusterName string

@description('Spark version for the cluster')
param SparkVersion string = '13.3.x-scala2.12'

@description('Node type ID for driver and worker nodes')
param NodeTypeId string = 'Standard_DS3_v2'

@description('Number of worker nodes (for fixed size clusters)')
param NumWorkers int = 2

@description('Minimum number of workers for autoscaling clusters')
param MinWorkers int?

@description('Maximum number of workers for autoscaling clusters')
param MaxWorkers int?

@description('Whether to enable autoscaling')
param AutoScale bool = false

@description('Whether to automatically terminate the cluster after inactivity')
param AutoTerminationMinutes int = 60

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Custom tags for the cluster')
param CustomTags object = {}

@description('Spark configuration properties')
param SparkConf object = {}

@description('Environment variables for Spark')
param SparkEnvVars object = {}

@description('Init scripts for cluster initialization')
param InitScripts array = []

@description('Driver node type ID (defaults to NodeTypeId if not specified)')
param DriverNodeTypeId string = ''

@description('Whether to enable local SSD for worker nodes')
param EnableLocalSsd bool = false

@description('Instance pool ID to use for the cluster')
param InstancePoolId string = ''

@description('Policy ID to apply to the cluster')
param PolicyId string = ''

@description('Runtime engine type')
@allowed(['STANDARD', 'PHOTON'])
param RuntimeEngine string = 'STANDARD'

var actualDriverNodeTypeId = empty(DriverNodeTypeId) ? NodeTypeId : DriverNodeTypeId

var clusterConfig = {
  cluster_name: ClusterName
  spark_version: SparkVersion
  node_type_id: NodeTypeId
  driver_node_type_id: actualDriverNodeTypeId
  num_workers: AutoScale ? null : NumWorkers
  autoscale: AutoScale ? {
    min_workers: MinWorkers
    max_workers: MaxWorkers
  } : null
  auto_termination_minutes: AutoTerminationMinutes
  custom_tags: CustomTags
  spark_conf: SparkConf
  spark_env_vars: SparkEnvVars
  init_scripts: InitScripts
  enable_local_ssd: EnableLocalSsd
  instance_pool_id: empty(InstancePoolId) ? null : InstancePoolId
  policy_id: empty(PolicyId) ? null : PolicyId
  runtime_engine: RuntimeEngine
}

resource clusterCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-cluster-${uniqueString(ClusterName)}'
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
        name: 'CLUSTER_CONFIG'
        value: string(clusterConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create cluster
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/clusters/create" `
        -Body $env:CLUSTER_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $cluster = $createResponse | ConvertFrom-Json
      
      # Wait for cluster to be ready
      $clusterId = $cluster.cluster_id
      $maxAttempts = 30
      $attempt = 0
      
      do {
        Start-Sleep -Seconds 30
        $attempt++
        
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.1/clusters/get?cluster_id=$clusterId" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $status = ($statusResponse | ConvertFrom-Json).state
        Write-Host "Cluster status: $status (attempt $attempt/$maxAttempts)"
        
        if ($status -eq "RUNNING") {
          break
        }
        elseif ($status -in @("ERROR", "TERMINATED")) {
          throw "Cluster creation failed with status: $status"
        }
      } while ($attempt -lt $maxAttempts)
      
      if ($attempt -ge $maxAttempts) {
        throw "Cluster creation timed out after $maxAttempts attempts"
      }
      
      $DeploymentScriptOutputs = @{
        clusterId = $clusterId
        clusterName = $cluster.cluster_name
        state = $status
        sparkVersion = $cluster.spark_version
        nodeTypeId = $cluster.node_type_id
        driverNodeTypeId = $cluster.driver_node_type_id
        numWorkers = $cluster.num_workers
      }
    '''
  }
}

@description('The ID of the created Databricks cluster')
output ClusterId string = clusterCreation.properties.outputs.clusterId

@description('The name of the created Databricks cluster')
output ClusterName string = clusterCreation.properties.outputs.clusterName

@description('The current state of the cluster')
output State string = clusterCreation.properties.outputs.state

@description('The Spark version of the cluster')
output SparkVersion string = clusterCreation.properties.outputs.sparkVersion

@description('The node type ID used for worker nodes')
output NodeTypeId string = clusterCreation.properties.outputs.nodeTypeId

@description('The node type ID used for the driver node')
output DriverNodeTypeId string = clusterCreation.properties.outputs.driverNodeTypeId

@description('The number of worker nodes in the cluster')
output NumWorkers int = int(clusterCreation.properties.outputs.numWorkers)
