@description('Path where the notebook will be stored in Databricks workspace')
param NotebookPath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Programming language of the notebook')
@allowed(['SCALA', 'PYTHON', 'SQL', 'R'])
param Language string = 'PYTHON'

@description('Format of the notebook content')
@allowed(['SOURCE', 'HTML', 'JUPYTER', 'DBC'])
param Format string = 'SOURCE'

@description('Base64-encoded content of the notebook')
param Content string = ''

@description('Source file path for notebook content (alternative to Content)')
param SourcePath string = ''

@description('Whether to overwrite existing notebook')
param Overwrite bool = false

var notebookConfig = {
  path: NotebookPath
  language: Language
  format: Format
  content: empty(Content) ? null : Content
  overwrite: Overwrite
}

resource notebookCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-notebook-${uniqueString(NotebookPath)}'
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
        name: 'NOTEBOOK_CONFIG'
        value: string(notebookConfig)
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
      
      $config = $env:NOTEBOOK_CONFIG | ConvertFrom-Json
      
      # If source path is provided, read and encode the content
      if (-not [string]::IsNullOrEmpty($env:SOURCE_PATH) -and (Test-Path $env:SOURCE_PATH)) {
        $sourceContent = Get-Content -Path $env:SOURCE_PATH -Raw
        $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sourceContent))
        $config.content = $encodedContent
      }
      
      # If no content provided, create a default notebook
      if ([string]::IsNullOrEmpty($config.content)) {
        $defaultContent = switch ($config.language) {
          "PYTHON" { "# Databricks notebook source`n`nprint(`"Hello, Databricks!`")" }
          "SCALA" { "// Databricks notebook source`n`nprintln(`"Hello, Databricks!`")" }
          "SQL" { "-- Databricks notebook source`n`nSELECT `"Hello, Databricks!`" as greeting" }
          "R" { "# Databricks notebook source`n`nprint(`"Hello, Databricks!`")" }
        }
        $config.content = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($defaultContent))
      }
      
      # Import notebook
      $importResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/workspace/import" `
        -Body ($config | ConvertTo-Json -Depth 10) `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get notebook status
      $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($config.path))" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $status = $statusResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        notebookPath = $status.path
        language = $status.language
        objectType = $status.object_type
        objectId = $status.object_id
      }
    '''
  }
}

@description('The path of the created notebook')
output NotebookPath string = notebookCreation.properties.outputs.notebookPath

@description('The programming language of the notebook')
output Language string = notebookCreation.properties.outputs.language

@description('The object type of the notebook')
output ObjectType string = notebookCreation.properties.outputs.objectType

@description('The unique object ID of the notebook')
output ObjectId int = int(notebookCreation.properties.outputs.objectId)
