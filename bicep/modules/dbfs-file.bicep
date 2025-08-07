@description('Path where the file will be stored in DBFS')
param FilePath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Base64-encoded content of the file')
param Content string = ''

@description('Source file path for file content (alternative to Content)')
param SourcePath string = ''

@description('Whether to overwrite existing file')
param Overwrite bool = false

var fileConfig = {
  path: FilePath
  contents: empty(Content) ? null : Content
  overwrite: Overwrite
}

resource dbfsFileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-dbfs-file-${uniqueString(FilePath)}'
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
        name: 'FILE_CONFIG'
        value: string(fileConfig)
      }
      {
        name: 'SOURCE_PATH'
        value: SourcePath
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $config = $env:FILE_CONFIG | ConvertFrom-Json
      
      # If source path is provided, read and encode the content
      if (-not [string]::IsNullOrEmpty($env:SOURCE_PATH) -and (Test-Path $env:SOURCE_PATH)) {
        $sourceContent = Get-Content -Path $env:SOURCE_PATH -Raw -Encoding UTF8
        $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourceContent))
        $config.contents = $encodedContent
      }
      
      # If no content provided, create a default file
      if ([string]::IsNullOrEmpty($config.contents)) {
        $defaultContent = "# Default DBFS file content`nCreated by Bicep module"
        $config.contents = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($defaultContent))
      }
      
      # Upload file to DBFS
      $uploadResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/dbfs/put" `
        -Body ($config | ConvertTo-Json -Depth 10) `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get file status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/dbfs/get-status?path=$([System.Web.HttpUtility]::UrlEncode($config.path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        filePath = $status.path
        fileSize = $status.file_size
        isDirectory = $status.is_dir
        modificationTime = $status.modification_time
      }
    '''
  }
}

@description('The path of the created DBFS file')
output FilePath string = dbfsFileCreation.properties.outputs.filePath

@description('The size of the file in bytes')
output FileSize int = int(dbfsFileCreation.properties.outputs.fileSize)

@description('Whether the path is a directory')
output IsDirectory bool = bool(dbfsFileCreation.properties.outputs.isDirectory)

@description('The modification timestamp of the file')
output ModificationTime int = int(dbfsFileCreation.properties.outputs.modificationTime)
