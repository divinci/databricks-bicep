@description('Databricks Infrastructure using Custom Resource Provider')
param databricksProviderName string
param databricksProviderResourceGroup string = resourceGroup().name
param environment string = 'production'
param clusterConfig object = {
  nodeTypeId: 'Standard_DS3_v2'
  numWorkers: 3
  sparkVersion: '15.4.x-scala2.12'
  runtimeEngine: 'STANDARD'
}

// Reference existing Databricks custom provider
resource databricksProvider 'Microsoft.CustomProviders/resourceProviders@2018-09-01-preview' existing = {
  name: databricksProviderName
  scope: resourceGroup(databricksProviderResourceGroup)
}

// Create Databricks cluster via custom provider
resource productionCluster 'Microsoft.CustomProviders/resourceProviders/clusters@2018-09-01-preview' = {
  name: '${databricksProviderName}/${environment}-analytics-cluster'
  location: 'East US'
  properties: {
    clusterName: '${environment}-analytics-cluster'
    nodeTypeId: clusterConfig.nodeTypeId
    numWorkers: clusterConfig.numWorkers
    sparkVersion: clusterConfig.sparkVersion
    runtimeEngine: clusterConfig.runtimeEngine
    autoterminationMinutes: 120
    azureAttributes: {
      availability: 'ON_DEMAND_AZURE'
      firstOnDemand: 1
      spotBidPricePercent: 100
    }
    sparkConf: {
      'spark.databricks.cluster.profile': 'serverless'
      'spark.databricks.repl.allowedLanguages': 'python,sql,scala,r'
      'spark.databricks.delta.preview.enabled': 'true'
    }
    sparkEnvVars: {
      ENVIRONMENT: environment
      CLUSTER_TYPE: 'analytics'
    }
    dataSecurityMode: 'USER_ISOLATION'
    enableElasticDisk: true
    enableLocalSsdEncryption: true
    initScripts: [
      {
        dbfs: {
          destination: 'dbfs:/databricks/init-scripts/cluster-setup.sh'
        }
      }
    ]
  }
}

// Create ML cluster for machine learning workloads
resource mlCluster 'Microsoft.CustomProviders/resourceProviders/clusters@2018-09-01-preview' = {
  name: '${databricksProviderName}/${environment}-ml-cluster'
  location: 'East US'
  properties: {
    clusterName: '${environment}-ml-cluster'
    nodeTypeId: 'Standard_NC6s_v3'
    numWorkers: 2
    sparkVersion: '15.4.x-scala2.12'
    runtimeEngine: 'STANDARD'
    autoterminationMinutes: 60
    azureAttributes: {
      availability: 'ON_DEMAND_AZURE'
      firstOnDemand: 1
    }
    sparkConf: {
      'spark.databricks.cluster.profile': 'ml'
      'spark.databricks.ml.automl.enabled': 'true'
    }
    dataSecurityMode: 'SINGLE_USER'
    singleUserName: 'ml-engineer@company.com'
    useMLRuntime: true
    enableElasticDisk: true
  }
}

// Create instance pool for cost optimization
resource sharedInstancePool 'Microsoft.CustomProviders/resourceProviders/instancePools@2018-09-01-preview' = {
  name: '${databricksProviderName}/${environment}-shared-pool'
  location: 'East US'
  properties: {
    instancePoolName: '${environment}-shared-instance-pool'
    nodeTypeId: 'Standard_DS3_v2'
    minIdleInstances: 0
    maxCapacity: 10
    idleInstanceAutoterminationMinutes: 15
    azureAttributes: {
      availability: 'SPOT_WITH_FALLBACK_AZURE'
      spotBidPricePercent: 50
    }
    enableElasticDisk: true
    diskSpec: {
      diskType: {
        azureDiskVolumeType: 'PREMIUM_LRS'
      }
      diskSize: 100
      diskCount: 1
    }
  }
}

// Create ETL job
resource etlJob 'Microsoft.CustomProviders/resourceProviders/jobs@2018-09-01-preview' = {
  name: '${databricksProviderName}/${environment}-daily-etl'
  location: 'East US'
  properties: {
    jobName: '${environment}-daily-etl-pipeline'
    tasks: [
      {
        taskKey: 'extract-data'
        notebookTask: {
          notebookPath: '/Shared/ETL/extract_data'
          baseParameters: {
            environment: environment
            date: '{{ds}}'
          }
        }
        newCluster: {
          nodeTypeId: 'Standard_DS3_v2'
          numWorkers: 2
          sparkVersion: '15.4.x-scala2.12'
          sparkConf: {
            'spark.databricks.delta.optimizeWrite.enabled': 'true'
          }
        }
        timeoutSeconds: 3600
        maxRetries: 2
      }
      {
        taskKey: 'transform-data'
        dependsOn: [
          {
            taskKey: 'extract-data'
          }
        ]
        sparkJarTask: {
          mainClassName: 'com.company.etl.TransformData'
          parameters: [
            '--environment'
            environment
            '--input-path'
            '/mnt/raw-data'
            '--output-path'
            '/mnt/processed-data'
          ]
        }
        existingClusterId: productionCluster.properties.clusterId
        timeoutSeconds: 7200
        maxRetries: 1
      }
    ]
    schedule: {
      quartzCronExpression: '0 0 2 * * ?'
      timezoneId: 'UTC'
      pauseStatus: 'UNPAUSED'
    }
    emailNotifications: {
      onStart: ['data-team@company.com']
      onSuccess: ['data-team@company.com']
      onFailure: ['data-team@company.com', 'oncall@company.com']
    }
    maxConcurrentRuns: 1
    format: 'MULTI_TASK'
  }
}

output productionClusterId string = productionCluster.properties.clusterId
output mlClusterId string = mlCluster.properties.clusterId
output instancePoolId string = sharedInstancePool.properties.instancePoolId
output etlJobId string = etlJob.properties.jobId
