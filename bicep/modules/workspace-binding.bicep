@description('Catalog name for the workspace binding')
param CatalogName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Workspace ID for the binding')
param WorkspaceId string

@description('Binding type for the workspace binding')
@allowed(['BINDING_TYPE_READ_WRITE', 'BINDING_TYPE_READ_ONLY'])
param BindingType string = 'BINDING_TYPE_READ_WRITE'

var bindingConfig = {
  catalog_name: CatalogName
  workspace_id: WorkspaceId
  binding_type: BindingType
}

resource workspaceBindingCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-workspace-binding-${uniqueString(CatalogName, WorkspaceId)}'
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
        name: 'BINDING_CONFIG'
        value: string(bindingConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $bindingConfigObj = $env:BINDING_CONFIG | ConvertFrom-Json
      
      # Create workspace binding
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/bindings" `
        -Body $env:BINDING_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get workspace binding details
      $bindingDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/bindings/$($bindingConfigObj.catalog_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $bindingDetails = $bindingDetailsResponse | ConvertFrom-Json
      $binding = $bindingDetails.bindings | Where-Object { $_.workspace_id -eq $bindingConfigObj.workspace_id }
      
      $DeploymentScriptOutputs = @{
        catalogName = $bindingConfigObj.catalog_name
        workspaceId = $binding.workspace_id
        bindingType = $binding.binding_type
      }
    '''
  }
}

@description('The catalog name of the workspace binding')
output CatalogName string = workspaceBindingCreation.properties.outputs.catalogName

@description('The workspace ID of the binding')
output WorkspaceId string = workspaceBindingCreation.properties.outputs.workspaceId

@description('The binding type of the workspace binding')
output BindingType string = workspaceBindingCreation.properties.outputs.bindingType
