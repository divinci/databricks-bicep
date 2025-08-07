@description('Name of the global init script')
param ScriptName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Base64-encoded content of the script')
param Content string = ''

@description('Source file path for script content (alternative to Content)')
param SourcePath string = ''

@description('Whether the script is enabled')
param Enabled bool = true

@description('Position/order of the script execution')
param Position int = 0

var scriptConfig = {
  name: ScriptName
  script: empty(Content) ? null : Content
  enabled: Enabled
  position: Position
}

resource globalInitScriptCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-global-init-script-${uniqueString(ScriptName)}'
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
        name: 'SCRIPT_CONFIG'
        value: string(scriptConfig)
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
      
      $config = $env:SCRIPT_CONFIG | ConvertFrom-Json
      
      # If source path is provided, read and encode the content
      if (-not [string]::IsNullOrEmpty($env:SOURCE_PATH) -and (Test-Path $env:SOURCE_PATH)) {
        $sourceContent = Get-Content -Path $env:SOURCE_PATH -Raw -Encoding UTF8
        $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourceContent))
        $config.script = $encodedContent
      }
      
      # If no content provided, create a default script
      if ([string]::IsNullOrEmpty($config.script)) {
        $defaultScript = @"
#!/bin/bash
# Default global init script created by Bicep module
echo "Global init script: $($config.name) executed at `$(date)"
"@
        $config.script = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($defaultScript))
      }
      
      # Create global init script
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/global-init-scripts" `
        -Body ($config | ConvertTo-Json -Depth 10) `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $script = $createResponse | ConvertFrom-Json
      $scriptId = $script.script_id
      
      # Get script details
      $scriptDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/global-init-scripts/$scriptId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $scriptDetails = $scriptDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        scriptId = $scriptId
        scriptName = $scriptDetails.name
        enabled = $scriptDetails.enabled
        position = $scriptDetails.position
        createdBy = $scriptDetails.created_by
        createdAt = $scriptDetails.created_at
      }
    '''
  }
}

@description('The ID of the created global init script')
output ScriptId string = globalInitScriptCreation.properties.outputs.scriptId

@description('The name of the global init script')
output ScriptName string = globalInitScriptCreation.properties.outputs.scriptName

@description('Whether the script is enabled')
output Enabled bool = bool(globalInitScriptCreation.properties.outputs.enabled)

@description('The position/order of the script execution')
output Position int = int(globalInitScriptCreation.properties.outputs.position)

@description('The user who created the script')
output CreatedBy string = globalInitScriptCreation.properties.outputs.createdBy

@description('The creation timestamp of the script')
output CreatedAt int = int(globalInitScriptCreation.properties.outputs.createdAt)
