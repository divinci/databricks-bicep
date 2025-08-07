@description('Name of the mount point')
param MountName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Source URI for the mount (e.g., abfss://container@storage.dfs.core.windows.net/)')
param Source string

@description('Extra configurations for the mount')
param ExtraConfigs object = {}

@description('Encryption type for the mount')
@allowed(['', 'sse-s3', 'sse-kms'])
param EncryptionType string = ''

var mountConfig = {
  source: Source
  mount_name: MountName
  extra_configs: ExtraConfigs
  encryption_type: empty(EncryptionType) ? null : EncryptionType
}

resource mountCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mount-${uniqueString(MountName)}'
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
        name: 'MOUNT_CONFIG'
        value: string(mountConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $config = $env:MOUNT_CONFIG | ConvertFrom-Json
      
      # Check if mount already exists
      $listMountsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/dbfs/list?path=/mnt/" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $existingMounts = $listMountsResponse | ConvertFrom-Json
      $mountExists = $existingMounts.files | Where-Object { $_.path -eq "/mnt/$($config.mount_name)" }
      
      if ($mountExists) {
        Write-Host "Mount $($config.mount_name) already exists, unmounting first..."
        
        # Unmount existing mount
        $unmountBody = @{
          mount_name = $config.mount_name
        } | ConvertTo-Json
        
        & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "POST" `
          -UrlPath "/api/2.0/dbfs/unmount" `
          -Body $unmountBody `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
      }
      
      # Create mount
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/dbfs/mount" `
        -Body ($config | ConvertTo-Json -Depth 10) `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Verify mount was created
      $verifyResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/dbfs/list?path=/mnt/$($config.mount_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $DeploymentScriptOutputs = @{
        mountName = $config.mount_name
        source = $config.source
        mountPath = "/mnt/$($config.mount_name)"
      }
    '''
  }
}

@description('The name of the created mount')
output MountName string = mountCreation.properties.outputs.mountName

@description('The source URI of the mount')
output Source string = mountCreation.properties.outputs.source

@description('The full mount path in DBFS')
output MountPath string = mountCreation.properties.outputs.mountPath
