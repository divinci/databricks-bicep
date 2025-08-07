@description('Path of the workspace file')
param Path string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Content of the workspace file')
param Content string = ''

@description('Source path for the workspace file')
param Source string = ''

@description('Language of the workspace file')
@allowed(['SCALA', 'PYTHON', 'SQL', 'R'])
param Language string = 'PYTHON'

@description('Format of the workspace file')
@allowed(['SOURCE', 'HTML', 'JUPYTER', 'DBC'])
param Format string = 'SOURCE'

@description('Whether to overwrite existing file')
param Overwrite bool = false

var fileConfig = {
  path: Path
  content: empty(Content) ? null : Content
  language: Language
  format: Format
  overwrite: Overwrite
}

resource workspaceFileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-file-${uniqueString(Path)}'
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
        value: Source
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $fileConfigObj = $env:FILE_CONFIG | ConvertFrom-Json
      
      # If source path is provided, read content from source
      if (-not [string]::IsNullOrEmpty($env:SOURCE_PATH)) {
        if (Test-Path $env:SOURCE_PATH) {
          $sourceContent = Get-Content $env:SOURCE_PATH -Raw
          $fileConfigObj.content = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourceContent))
        }
      } elseif (-not [string]::IsNullOrEmpty($fileConfigObj.content)) {
        # Encode content as base64
        $fileConfigObj.content = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileConfigObj.content))
      }
      
      $fileConfigJson = $fileConfigObj | ConvertTo-Json -Depth 10
      
      # Import workspace file
      $importResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/workspace/import" `
        -Body $fileConfigJson `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get workspace object info
      $objectInfoResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($fileConfigObj.path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $objectInfo = $objectInfoResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        path = $objectInfo.path
        objectType = $objectInfo.object_type
        objectId = $objectInfo.object_id
        language = $objectInfo.language
        createdAt = $objectInfo.created_at
        modifiedAt = $objectInfo.modified_at
      }
    '''
  }
}

@description('The path of the workspace file')
output Path string = workspaceFileCreation.properties.outputs.path

@description('The object type of the workspace file')
output ObjectType string = workspaceFileCreation.properties.outputs.objectType

@description('The object ID of the workspace file')
output ObjectId int = int(workspaceFileCreation.properties.outputs.objectId)

@description('The language of the workspace file')
output Language string = workspaceFileCreation.properties.outputs.language

@description('The creation timestamp of the workspace file')
output CreatedAt int = int(workspaceFileCreation.properties.outputs.createdAt)

@description('The modification timestamp of the workspace file')
output ModifiedAt int = int(workspaceFileCreation.properties.outputs.modifiedAt)
