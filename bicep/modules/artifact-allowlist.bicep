@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Artifact matcher configuration')
param ArtifactMatchers array

@description('Created by user ID')
param CreatedBy int = 0

@description('Metastore ID for the allowlist')
param MetastoreId string = ''

var allowlistConfig = {
  artifact_matchers: ArtifactMatchers
  created_by: CreatedBy == 0 ? null : CreatedBy
  metastore_id: empty(MetastoreId) ? null : MetastoreId
}

resource artifactAllowlistCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-artifact-allowlist-${uniqueString(resourceGroup().id)}'
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
        name: 'ALLOWLIST_CONFIG'
        value: string(allowlistConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create artifact allowlist
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.1/unity-catalog/artifact-allowlists" `
        -Body $env:ALLOWLIST_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $allowlist = $createResponse | ConvertFrom-Json
      
      # Get allowlist details
      $allowlistDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/artifact-allowlists" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $allowlistDetails = $allowlistDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        artifactMatchers = ($allowlistDetails.artifact_matchers | ConvertTo-Json -Compress)
        createdBy = $allowlistDetails.created_by
        createdAt = $allowlistDetails.created_at
        metastoreId = $allowlistDetails.metastore_id
      }
    '''
  }
}

@description('The artifact matchers configuration')
output ArtifactMatchers string = artifactAllowlistCreation.properties.outputs.artifactMatchers

@description('The user ID who created the allowlist')
output CreatedBy int = int(artifactAllowlistCreation.properties.outputs.createdBy)

@description('The creation timestamp of the allowlist')
output CreatedAt int = int(artifactAllowlistCreation.properties.outputs.createdAt)

@description('The metastore ID of the allowlist')
output MetastoreId string = artifactAllowlistCreation.properties.outputs.metastoreId
