@description('Principal ID for the entitlements')
param PrincipalId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Allow cluster create entitlement')
param AllowClusterCreate bool = false

@description('Allow instance pool create entitlement')
param AllowInstancePoolCreate bool = false

@description('Databricks SQL access entitlement')
param DatabricksSqlAccess bool = false

@description('Workspace access entitlement')
param WorkspaceAccess bool = false

var entitlementsConfig = {
  schemas = @[
    'urn:ietf:params:scim:schemas:core:2.0:User'
    'urn:ietf:params:scim:schemas:extension:workspace:2.0:User'
  ]
  entitlements = [
    {
      value: 'allow-cluster-create'
    }
    {
      value: 'allow-instance-pool-create'
    }
    {
      value: 'databricks-sql-access'
    }
    {
      value: 'workspace-access'
    }
  ]
}

resource entitlementsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-entitlements-${uniqueString(PrincipalId)}'
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
        name: 'PRINCIPAL_ID'
        value: PrincipalId
      }
      {
        name: 'ALLOW_CLUSTER_CREATE'
        value: string(AllowClusterCreate)
      }
      {
        name: 'ALLOW_INSTANCE_POOL_CREATE'
        value: string(AllowInstancePoolCreate)
      }
      {
        name: 'DATABRICKS_SQL_ACCESS'
        value: string(DatabricksSqlAccess)
      }
      {
        name: 'WORKSPACE_ACCESS'
        value: string(WorkspaceAccess)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Build entitlements array based on parameters
      $entitlements = @()
      if ($env:ALLOW_CLUSTER_CREATE -eq "True") {
        $entitlements += @{ value = "allow-cluster-create" }
      }
      if ($env:ALLOW_INSTANCE_POOL_CREATE -eq "True") {
        $entitlements += @{ value = "allow-instance-pool-create" }
      }
      if ($env:DATABRICKS_SQL_ACCESS -eq "True") {
        $entitlements += @{ value = "databricks-sql-access" }
      }
      if ($env:WORKSPACE_ACCESS -eq "True") {
        $entitlements += @{ value = "workspace-access" }
      }
      
      $entitlementsConfig = @{
        schemas = @(
          "urn:ietf:params:scim:schemas:core:2.0:User",
          "urn:ietf:params:scim:schemas:extension:workspace:2.0:User"
        )
        entitlements = $entitlements
      } | ConvertTo-Json -Depth 10
      
      # Update user entitlements
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PATCH" `
        -UrlPath "/api/2.0/scim/v2/Users/$($env:PRINCIPAL_ID)" `
        -Body $entitlementsConfig `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $user = $updateResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        principalId = $user.id
        entitlements = ($user.entitlements | ConvertTo-Json -Compress)
        allowClusterCreate = ($user.entitlements | Where-Object { $_.value -eq "allow-cluster-create" }) -ne $null
        allowInstancePoolCreate = ($user.entitlements | Where-Object { $_.value -eq "allow-instance-pool-create" }) -ne $null
        databricksSqlAccess = ($user.entitlements | Where-Object { $_.value -eq "databricks-sql-access" }) -ne $null
        workspaceAccess = ($user.entitlements | Where-Object { $_.value -eq "workspace-access" }) -ne $null
      }
    '''
  }
}

@description('The principal ID for the entitlements')
output PrincipalId string = entitlementsCreation.properties.outputs.principalId

@description('The entitlements configuration')
output Entitlements string = entitlementsCreation.properties.outputs.entitlements

@description('Whether cluster create is allowed')
output AllowClusterCreate bool = bool(entitlementsCreation.properties.outputs.allowClusterCreate)

@description('Whether instance pool create is allowed')
output AllowInstancePoolCreate bool = bool(entitlementsCreation.properties.outputs.allowInstancePoolCreate)

@description('Whether Databricks SQL access is granted')
output DatabricksSqlAccess bool = bool(entitlementsCreation.properties.outputs.databricksSqlAccess)

@description('Whether workspace access is granted')
output WorkspaceAccess bool = bool(entitlementsCreation.properties.outputs.workspaceAccess)
