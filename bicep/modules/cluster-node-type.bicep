@description('Node type ID')
param NodeTypeId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether to include local disk information')
param IncludeLocalDisk bool = false

resource clusterNodeTypeCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-cluster-node-type-${uniqueString(NodeTypeId)}'
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
        name: 'NODE_TYPE_ID'
        value: NodeTypeId
      }
      {
        name: 'INCLUDE_LOCAL_DISK'
        value: string(IncludeLocalDisk)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # List node types
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/clusters/list-node-types" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $nodeTypes = $listResponse | ConvertFrom-Json
      $nodeType = $nodeTypes.node_types | Where-Object { $_.node_type_id -eq $env:NODE_TYPE_ID }
      
      if (-not $nodeType) {
        throw "Node type $($env:NODE_TYPE_ID) not found"
      }
      
      $DeploymentScriptOutputs = @{
        nodeTypeId = $nodeType.node_type_id
        memoryMb = $nodeType.memory_mb
        numCores = $nodeType.num_cores
        description = $nodeType.description
        instanceTypeId = $nodeType.instance_type_id
        isIoOptimized = $nodeType.is_io_optimized
        numGpus = $nodeType.num_gpus
        nodeInfo = ($nodeType.node_info | ConvertTo-Json -Compress)
      }
      
      if ($env:INCLUDE_LOCAL_DISK -eq "True" -and $nodeType.node_instance_type) {
        $DeploymentScriptOutputs.localDisks = $nodeType.node_instance_type.local_disks
        $DeploymentScriptOutputs.localDiskSizeGb = $nodeType.node_instance_type.local_disk_size_gb
      }
    '''
  }
}

@description('The node type ID')
output NodeTypeId string = clusterNodeTypeCreation.properties.outputs.nodeTypeId

@description('Memory in MB')
output MemoryMb int = int(clusterNodeTypeCreation.properties.outputs.memoryMb)

@description('Number of cores')
output NumCores int = int(clusterNodeTypeCreation.properties.outputs.numCores)

@description('Node type description')
output Description string = clusterNodeTypeCreation.properties.outputs.description

@description('Instance type ID')
output InstanceTypeId string = clusterNodeTypeCreation.properties.outputs.instanceTypeId

@description('Whether IO optimized')
output IsIoOptimized bool = bool(clusterNodeTypeCreation.properties.outputs.isIoOptimized)

@description('Number of GPUs')
output NumGpus int = int(clusterNodeTypeCreation.properties.outputs.numGpus)

@description('Node information')
output NodeInfo string = clusterNodeTypeCreation.properties.outputs.nodeInfo

@description('Number of local disks')
output LocalDisks int = IncludeLocalDisk ? int(clusterNodeTypeCreation.properties.outputs.localDisks) : 0

@description('Local disk size in GB')
output LocalDiskSizeGb int = IncludeLocalDisk ? int(clusterNodeTypeCreation.properties.outputs.localDiskSizeGb) : 0
