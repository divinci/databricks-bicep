@description('Asset path in the workspace')
param AssetPath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Asset type')
@allowed(['NOTEBOOK', 'DIRECTORY', 'LIBRARY', 'FILE'])
param AssetType string

@description('Asset content (base64 encoded for binary files)')
param Content string = ''

@description('Asset language for notebooks')
@allowed(['PYTHON', 'SQL', 'SCALA', 'R'])
param Language string = 'PYTHON'

@description('Asset format')
@allowed(['SOURCE', 'HTML', 'JUPYTER', 'DBC'])
param Format string = 'SOURCE'

@description('Whether to overwrite existing asset')
param Overwrite bool = false

var assetConfig = {
  path: AssetPath
  content: Content
  language: Language
  format: Format
  overwrite: Overwrite
}

resource workspaceAssetCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-asset-${uniqueString(AssetPath)}'
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
        name: 'ASSET_CONFIG'
        value: string(assetConfig)
      }
      {
        name: 'ASSET_TYPE'
        value: AssetType
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $assetConfigObj = $env:ASSET_CONFIG | ConvertFrom-Json
      
      if ($env:ASSET_TYPE -eq "DIRECTORY") {
        # Create directory
        $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "POST" `
          -UrlPath "/api/2.0/workspace/mkdirs" `
          -Body (@{ path = $assetConfigObj.path } | ConvertTo-Json) `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
      } else {
        # Import file/notebook
        $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "POST" `
          -UrlPath "/api/2.0/workspace/import" `
          -Body $env:ASSET_CONFIG `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
      }
      
      # Get asset details
      $assetDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($assetConfigObj.path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $assetDetails = $assetDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        assetPath = $assetDetails.path
        objectType = $assetDetails.object_type
        objectId = $assetDetails.object_id
        language = $assetDetails.language
        createdAt = $assetDetails.created_at
        modifiedAt = $assetDetails.modified_at
      }
    '''
  }
}

@description('The asset path')
output AssetPath string = workspaceAssetCreation.properties.outputs.assetPath

@description('The object type of the asset')
output ObjectType string = workspaceAssetCreation.properties.outputs.objectType

@description('The object ID of the asset')
output ObjectId int = int(workspaceAssetCreation.properties.outputs.objectId)

@description('The language of the asset')
output Language string = workspaceAssetCreation.properties.outputs.language

@description('The creation timestamp')
output CreatedAt int = int(workspaceAssetCreation.properties.outputs.createdAt)

@description('The last modified timestamp')
output ModifiedAt int = int(workspaceAssetCreation.properties.outputs.modifiedAt)
