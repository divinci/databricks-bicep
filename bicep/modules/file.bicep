@description('Path of the file in workspace')
param Path string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Content of the file (base64 encoded)')
param Content string

@description('Source path for the file')
param Source string = ''

@description('MD5 hash of the file content')
param ContentBase64Md5 string = ''

var fileConfig = {
  path: Path
  content: Content
  overwrite: true
}

resource fileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-file-${uniqueString(Path)}'
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
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create file
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/workspace/import" `
        -Body $env:FILE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get file details
      $fileDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode(($env:FILE_CONFIG | ConvertFrom-Json).path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $fileDetails = $fileDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        path = $fileDetails.path
        objectType = $fileDetails.object_type
        objectId = $fileDetails.object_id
        language = $fileDetails.language
        size = $fileDetails.size
        modifiedAt = $fileDetails.modified_at
      }
    '''
  }
}

@description('The path of the created file')
output Path string = fileCreation.properties.outputs.path

@description('The object type of the file')
output ObjectType string = fileCreation.properties.outputs.objectType

@description('The object ID of the file')
output ObjectId int = int(fileCreation.properties.outputs.objectId)

@description('The language of the file')
output Language string = fileCreation.properties.outputs.language

@description('The size of the file')
output Size int = int(fileCreation.properties.outputs.size)

@description('The last modified timestamp of the file')
output ModifiedAt int = int(fileCreation.properties.outputs.modifiedAt)
