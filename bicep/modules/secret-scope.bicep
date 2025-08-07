@description('Name of the Databricks secret scope')
param ScopeName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Backend type for the secret scope')
@allowed(['DATABRICKS', 'AZURE_KEYVAULT'])
param BackendType string = 'DATABRICKS'

@description('Azure Key Vault DNS name (required for AZURE_KEYVAULT backend)')
param KeyVaultDnsName string = ''

@description('Azure Key Vault resource ID (required for AZURE_KEYVAULT backend)')
param KeyVaultResourceId string = ''

@description('Initial manage principal for the scope')
param InitialManagePrincipal string = ''

var scopeConfig = {
  scope: ScopeName
  backend_type: BackendType
  backend_azure_keyvault: BackendType == 'AZURE_KEYVAULT' ? {
    dns_name: KeyVaultDnsName
    resource_id: KeyVaultResourceId
  } : null
  initial_manage_principal: empty(InitialManagePrincipal) ? null : InitialManagePrincipal
}

resource secretScopeCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-secret-scope-${uniqueString(ScopeName)}'
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
        name: 'SCOPE_CONFIG'
        value: string(scopeConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create secret scope
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/secrets/scopes/create" `
        -Body $env:SCOPE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # List scopes to get details
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/secrets/scopes/list" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $scopes = ($listResponse | ConvertFrom-Json).scopes
      $scope = $scopes | Where-Object { $_.name -eq $env:SCOPE_CONFIG.scope }
      
      if (-not $scope) {
        throw "Failed to find created scope: $($env:SCOPE_CONFIG.scope)"
      }
      
      $DeploymentScriptOutputs = @{
        scopeName = $scope.name
        backendType = $scope.backend_type
      }
    '''
  }
}

@description('The name of the created secret scope')
output ScopeName string = secretScopeCreation.properties.outputs.scopeName

@description('The backend type of the secret scope')
output BackendType string = secretScopeCreation.properties.outputs.backendType
