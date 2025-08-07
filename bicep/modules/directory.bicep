@description('Path of the directory in Databricks workspace')
param DirectoryPath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether to delete the directory if it exists')
param DeleteExisting bool = false

var directoryConfig = {
  path: DirectoryPath
}

resource directoryCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-directory-${uniqueString(DirectoryPath)}'
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
        name: 'DIRECTORY_CONFIG'
        value: string(directoryConfig)
      }
      {
        name: 'DELETE_EXISTING'
        value: string(DeleteExisting)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $config = $env:DIRECTORY_CONFIG | ConvertFrom-Json
      $deleteExisting = [bool]::Parse($env:DELETE_EXISTING)
      
      # Check if directory exists
      try {
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($config.path))" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $status = $statusResponse | ConvertFrom-Json
        
        if ($status.object_type -eq "DIRECTORY") {
          if ($deleteExisting) {
            Write-Host "Directory exists, deleting as requested..."
            $deleteBody = @{
              path = $config.path
              recursive = $true
            } | ConvertTo-Json
            
            & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
              -Method "POST" `
              -UrlPath "/api/2.0/workspace/delete" `
              -Body $deleteBody `
              -DatabricksToken $secureToken `
              -WorkspaceUrl $env:WORKSPACE_URL
          } else {
            Write-Host "Directory already exists: $($config.path)"
            $DeploymentScriptOutputs = @{
              directoryPath = $status.path
              objectType = $status.object_type
              objectId = $status.object_id
            }
            return
          }
        }
      }
      catch {
        # Directory doesn't exist, which is fine
        Write-Host "Directory doesn't exist, will create: $($config.path)"
      }
      
      # Create directory
      $createBody = @{
        path = $config.path
      } | ConvertTo-Json
      
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/workspace/mkdirs" `
        -Body $createBody `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get directory status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($config.path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        directoryPath = $status.path
        objectType = $status.object_type
        objectId = $status.object_id
      }
    '''
  }
}

@description('The path of the created directory')
output DirectoryPath string = directoryCreation.properties.outputs.directoryPath

@description('The object type of the directory')
output ObjectType string = directoryCreation.properties.outputs.objectType

@description('The unique object ID of the directory')
output ObjectId int = int(directoryCreation.properties.outputs.objectId)
