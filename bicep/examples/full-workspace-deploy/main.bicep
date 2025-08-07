@description('Name prefix for all resources')
param NamePrefix string = 'databricks-bicep'

@description('Azure region for deployment')
param Location string = resourceGroup().location

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Environment tag')
param Environment string = 'Development'

var commonTags = {
  Environment: Environment
  Project: 'Databricks-Bicep-Conversion'
  ManagedBy: 'Bicep'
}

// Create instance pool for shared compute resources
module instancePool '../modules/instance-pool.bicep' = {
  name: 'shared-instance-pool'
  params: {
    InstancePoolName: '${NamePrefix}-shared-pool'
    NodeTypeId: 'Standard_DS3_v2'
    MinIdleInstances: 1
    MaxCapacity: 10
    IdleInstanceAutoTerminationMinutes: 60
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    CustomTags: commonTags
    PreloadedSparkVersions: [
      '13.3.x-scala2.12'
      '12.2.x-scala2.12'
    ]
    EnableElasticDisk: true
    DiskSpec: {
      disk_type: {
        azure_disk_volume_type: 'PREMIUM_LRS'
      }
      disk_size: 100
      disk_count: 1
    }
  }
}

// Create production cluster using the instance pool
module productionCluster '../modules/cluster.bicep' = {
  name: 'production-cluster'
  dependsOn: [instancePool]
  params: {
    ClusterName: '${NamePrefix}-production-cluster'
    SparkVersion: '13.3.x-scala2.12'
    NodeTypeId: 'Standard_DS3_v2'
    AutoScale: true
    MinWorkers: 2
    MaxWorkers: 8
    AutoTerminationMinutes: 120
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    InstancePoolId: instancePool.outputs.InstancePoolId
    CustomTags: union(commonTags, {
      ClusterType: 'Production'
    })
    SparkConf: {
      'spark.sql.adaptive.enabled': 'true'
      'spark.sql.adaptive.coalescePartitions.enabled': 'true'
      'spark.databricks.delta.optimizeWrite.enabled': 'true'
    }
    RuntimeEngine: 'PHOTON'
  }
}

// Create development cluster with fixed size
module developmentCluster '../modules/cluster.bicep' = {
  name: 'development-cluster'
  params: {
    ClusterName: '${NamePrefix}-development-cluster'
    SparkVersion: '13.3.x-scala2.12'
    NodeTypeId: 'Standard_DS3_v2'
    NumWorkers: 2
    AutoTerminationMinutes: 60
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    CustomTags: union(commonTags, {
      ClusterType: 'Development'
    })
    SparkConf: {
      'spark.sql.adaptive.enabled': 'true'
    }
  }
}

// Create ETL job using the production cluster
module etlJob '../modules/job.bicep' = {
  name: 'etl-job'
  dependsOn: [productionCluster]
  params: {
    JobName: '${NamePrefix}-etl-job'
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    TimeoutSeconds: 7200
    MaxConcurrentRuns: 1
    JobSettings: {
      notebook_task: {
        notebook_path: '/Shared/ETL/daily-processing'
        base_parameters: {
          environment: Environment
          date: '{{ds}}'
        }
      }
      existing_cluster_id: productionCluster.outputs.ClusterId
      libraries: [
        {
          pypi: {
            package: 'pandas==1.5.3'
          }
        }
        {
          pypi: {
            package: 'numpy==1.24.3'
          }
        }
      ]
    }
    Schedule: {
      quartz_cron_expression: '0 0 2 * * ?'
      timezone_id: 'UTC'
    }
    EmailNotifications: {
      on_success: ['data-team@company.com']
      on_failure: ['data-team@company.com', 'ops-team@company.com']
    }
    Tags: union(commonTags, {
      JobType: 'ETL'
      Schedule: 'Daily'
    })
  }
}

// Create ML training job using the development cluster
module mlTrainingJob '../modules/job.bicep' = {
  name: 'ml-training-job'
  dependsOn: [developmentCluster]
  params: {
    JobName: '${NamePrefix}-ml-training-job'
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    TimeoutSeconds: 14400
    MaxConcurrentRuns: 1
    JobSettings: {
      python_wheel_task: {
        package_name: 'ml_training'
        entry_point: 'train'
        parameters: [
          '--model-type', 'xgboost'
          '--data-path', '/mnt/data/training'
          '--output-path', '/mnt/models/latest'
        ]
      }
      existing_cluster_id: developmentCluster.outputs.ClusterId
      libraries: [
        {
          whl: 'dbfs:/mnt/libraries/ml_training-1.0.0-py3-none-any.whl'
        }
        {
          pypi: {
            package: 'scikit-learn==1.3.0'
          }
        }
        {
          pypi: {
            package: 'xgboost==1.7.6'
          }
        }
      ]
    }
    Tags: union(commonTags, {
      JobType: 'ML-Training'
      Model: 'XGBoost'
    })
  }
}

// Create data validation job
module dataValidationJob '../modules/job.bicep' = {
  name: 'data-validation-job'
  params: {
    JobName: '${NamePrefix}-data-validation-job'
    DatabricksToken: DatabricksToken
    WorkspaceUrl: WorkspaceUrl
    TimeoutSeconds: 3600
    MaxConcurrentRuns: 3
    JobSettings: {
      spark_jar_task: {
        main_class_name: 'com.company.validation.DataValidator'
        parameters: [
          '--input-path', '/mnt/data/raw'
          '--rules-config', '/mnt/config/validation-rules.json'
          '--output-path', '/mnt/data/validated'
        ]
      }
      new_cluster: {
        spark_version: '13.3.x-scala2.12'
        node_type_id: 'Standard_DS3_v2'
        num_workers: 1
        spark_conf: {
          'spark.sql.adaptive.enabled': 'true'
        }
      }
      libraries: [
        {
          jar: 'dbfs:/mnt/libraries/data-validator-2.1.0.jar'
        }
      ]
    }
    Schedule: {
      quartz_cron_expression: '0 */4 * * * ?'
      timezone_id: 'UTC'
    }
    Tags: union(commonTags, {
      JobType: 'DataValidation'
      Schedule: 'Every4Hours'
    })
  }
}

@description('The ID of the shared instance pool')
output InstancePoolId string = instancePool.outputs.InstancePoolId

@description('The ID of the production cluster')
output ProductionClusterId string = productionCluster.outputs.ClusterId

@description('The ID of the development cluster')
output DevelopmentClusterId string = developmentCluster.outputs.ClusterId

@description('The ID of the ETL job')
output EtlJobId int = etlJob.outputs.JobId

@description('The ID of the ML training job')
output MlTrainingJobId int = mlTrainingJob.outputs.JobId

@description('The ID of the data validation job')
output DataValidationJobId int = dataValidationJob.outputs.JobId

@description('Summary of deployed resources')
output DeploymentSummary object = {
  instancePool: {
    id: instancePool.outputs.InstancePoolId
    name: instancePool.outputs.InstancePoolName
    state: instancePool.outputs.State
  }
  clusters: {
    production: {
      id: productionCluster.outputs.ClusterId
      name: productionCluster.outputs.ClusterName
      state: productionCluster.outputs.State
    }
    development: {
      id: developmentCluster.outputs.ClusterId
      name: developmentCluster.outputs.ClusterName
      state: developmentCluster.outputs.State
    }
  }
  jobs: {
    etl: {
      id: etlJob.outputs.JobId
      name: etlJob.outputs.JobName
    }
    mlTraining: {
      id: mlTrainingJob.outputs.JobId
      name: mlTrainingJob.outputs.JobName
    }
    dataValidation: {
      id: dataValidationJob.outputs.JobId
      name: dataValidationJob.outputs.JobName
    }
  }
}
