@description('Name of the SQL warehouse')
param WarehouseName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Cluster size for the warehouse')
@allowed(['2X-Small', 'X-Small', 'Small', 'Medium', 'Large', 'X-Large', '2X-Large', '3X-Large', '4X-Large'])
param ClusterSize string = 'X-Small'

@description('Minimum number of clusters')
param MinNumClusters int = 1

@description('Maximum number of clusters')
param MaxNumClusters int = 1

@description('Auto stop minutes')
param AutoStopMins int = 120

@description('Tags for the warehouse')
param Tags object = {}

@description('Spot instance policy')
@allowed(['COST_OPTIMIZED', 'RELIABILITY_OPTIMIZED'])
param SpotInstancePolicy string = 'COST_OPTIMIZED'

@description('Enable photon')
param EnablePhoton bool = true

@description('Enable serverless compute')
param EnableServerlessCompute bool = false

@description('Warehouse type')
@allowed(['PRO', 'CLASSIC'])
param WarehouseType string = 'PRO'

@description('Channel for the warehouse')
param Channel object = {}

var warehouseConfig = {
  name: WarehouseName
  cluster_size: ClusterSize
  min_num_clusters: MinNumClusters
  max_num_clusters: MaxNumClusters
  auto_stop_mins: AutoStopMins
  tags: empty(Tags) ? {} : Tags
  spot_instance_policy: SpotInstancePolicy
  enable_photon: EnablePhoton
  enable_serverless_compute: EnableServerlessCompute
  warehouse_type: WarehouseType
  channel: empty(Channel) ? {} : Channel
}

resource warehouseCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-warehouse-${uniqueString(WarehouseName)}'
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
        name: 'WAREHOUSE_CONFIG'
        value: string(warehouseConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create SQL warehouse
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/sql/warehouses" `
        -Body $env:WAREHOUSE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $warehouse = $createResponse | ConvertFrom-Json
      
      # Get warehouse details
      $warehouseDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/sql/warehouses/$($warehouse.id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $warehouseDetails = $warehouseDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        warehouseId = $warehouseDetails.id
        warehouseName = $warehouseDetails.name
        clusterSize = $warehouseDetails.cluster_size
        minNumClusters = $warehouseDetails.min_num_clusters
        maxNumClusters = $warehouseDetails.max_num_clusters
        autoStopMins = $warehouseDetails.auto_stop_mins
        spotInstancePolicy = $warehouseDetails.spot_instance_policy
        enablePhoton = $warehouseDetails.enable_photon
        enableServerlessCompute = $warehouseDetails.enable_serverless_compute
        warehouseType = $warehouseDetails.warehouse_type
        state = $warehouseDetails.state
        creatorName = $warehouseDetails.creator_name
        numClusters = $warehouseDetails.num_clusters
        numActiveSessions = $warehouseDetails.num_active_sessions
        jdbcUrl = $warehouseDetails.jdbc_url
        odbcParams = $warehouseDetails.odbc_params
      }
    '''
  }
}

@description('The ID of the created warehouse')
output WarehouseId string = warehouseCreation.properties.outputs.warehouseId

@description('The name of the warehouse')
output WarehouseName string = warehouseCreation.properties.outputs.warehouseName

@description('The cluster size of the warehouse')
output ClusterSize string = warehouseCreation.properties.outputs.clusterSize

@description('The minimum number of clusters')
output MinNumClusters int = int(warehouseCreation.properties.outputs.minNumClusters)

@description('The maximum number of clusters')
output MaxNumClusters int = int(warehouseCreation.properties.outputs.maxNumClusters)

@description('The auto stop minutes')
output AutoStopMins int = int(warehouseCreation.properties.outputs.autoStopMins)

@description('The spot instance policy')
output SpotInstancePolicy string = warehouseCreation.properties.outputs.spotInstancePolicy

@description('Whether photon is enabled')
output EnablePhoton bool = bool(warehouseCreation.properties.outputs.enablePhoton)

@description('Whether serverless compute is enabled')
output EnableServerlessCompute bool = bool(warehouseCreation.properties.outputs.enableServerlessCompute)

@description('The warehouse type')
output WarehouseType string = warehouseCreation.properties.outputs.warehouseType

@description('The current state of the warehouse')
output State string = warehouseCreation.properties.outputs.state

@description('The creator name of the warehouse')
output CreatorName string = warehouseCreation.properties.outputs.creatorName

@description('The current number of clusters')
output NumClusters int = int(warehouseCreation.properties.outputs.numClusters)

@description('The number of active sessions')
output NumActiveSessions int = int(warehouseCreation.properties.outputs.numActiveSessions)

@description('The JDBC URL for the warehouse')
output JdbcUrl string = warehouseCreation.properties.outputs.jdbcUrl

@description('The ODBC parameters for the warehouse')
output OdbcParams string = warehouseCreation.properties.outputs.odbcParams
