@description('Name of the storage configuration')
param StorageConfigurationName string

@description('Databricks Account ID')
param AccountId string

@description('Databricks Account Token')
@secure()
param AccountToken string

@description('S3 bucket name for the root storage')
param BucketName string

@description('S3 bucket region')
param BucketRegion string = ''

var storageConfig = {
  storage_configuration_name: StorageConfigurationName
  root_bucket_info: {
    bucket_name: BucketName
    bucket_region: empty(BucketRegion) ? null : BucketRegion
  }
}

resource mwsStorageConfigurationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-storage-${uniqueString(StorageConfigurationName)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'ACCOUNT_TOKEN'
        secureValue: AccountToken
      }
      {
        name: 'ACCOUNT_ID'
        value: AccountId
      }
      {
        name: 'STORAGE_CONFIG'
        value: string(storageConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:ACCOUNT_TOKEN -AsPlainText -Force
      
      # Create MWS storage configuration
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/storage-configurations" `
        -Body $env:STORAGE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $storageConfiguration = $createResponse | ConvertFrom-Json
      
      # Get storage configuration details
      $storageDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/storage-configurations/$($storageConfiguration.storage_configuration_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $storageDetails = $storageDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        storageConfigurationId = $storageDetails.storage_configuration_id
        storageConfigurationName = $storageDetails.storage_configuration_name
        bucketName = $storageDetails.root_bucket_info.bucket_name
        bucketRegion = $storageDetails.root_bucket_info.bucket_region
        creationTime = $storageDetails.creation_time
      }
    '''
  }
}

@description('The ID of the created storage configuration')
output StorageConfigurationId string = mwsStorageConfigurationCreation.properties.outputs.storageConfigurationId

@description('The name of the storage configuration')
output StorageConfigurationName string = mwsStorageConfigurationCreation.properties.outputs.storageConfigurationName

@description('The S3 bucket name')
output BucketName string = mwsStorageConfigurationCreation.properties.outputs.bucketName

@description('The S3 bucket region')
output BucketRegion string = mwsStorageConfigurationCreation.properties.outputs.bucketRegion

@description('The creation timestamp of the storage configuration')
output CreationTime int = int(mwsStorageConfigurationCreation.properties.outputs.creationTime)
