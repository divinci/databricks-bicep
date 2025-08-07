@description('Application ID of the service principal')
param ApplicationId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Display name for the service principal')
param DisplayName string = ''

@description('Whether the service principal is active')
param Active bool = true

@description('Entitlements for the service principal')
param Entitlements array = []

@description('External ID for the service principal')
param ExternalId string = ''

@description('Force creation even if service principal exists')
param Force bool = false

var servicePrincipalConfig = {
  applicationId: ApplicationId
  displayName: empty(DisplayName) ? ApplicationId : DisplayName
  active: Active
  entitlements: [for entitlement in Entitlements: {
    value: entitlement
  }]
  externalId: empty(ExternalId) ? null : ExternalId
}

resource servicePrincipalCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-service-principal-${uniqueString(ApplicationId)}'
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
        name: 'SERVICE_PRINCIPAL_CONFIG'
        value: string(servicePrincipalConfig)
      }
      {
        name: 'FORCE'
        value: string(Force)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $config = $env:SERVICE_PRINCIPAL_CONFIG | ConvertFrom-Json
      $force = [bool]::Parse($env:FORCE)
      
      # Check if service principal already exists
      $existingSpId = $null
      try {
        $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId eq `"$($config.applicationId)`"" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $existingSps = ($listResponse | ConvertFrom-Json).Resources
        if ($existingSps -and $existingSps.Count -gt 0) {
          $existingSpId = $existingSps[0].id
          if (-not $force) {
            Write-Host "Service principal already exists with ID: $existingSpId"
            $DeploymentScriptOutputs = @{
              servicePrincipalId = $existingSpId
              applicationId = $config.applicationId
              displayName = $existingSps[0].displayName
              active = $existingSps[0].active
            }
            return
          }
        }
      }
      catch {
        Write-Host "Service principal does not exist, will create new one"
      }
      
      # Create or update service principal
      if ($existingSpId -and $force) {
        # Update existing
        $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "PUT" `
          -UrlPath "/api/2.0/preview/scim/v2/ServicePrincipals/$existingSpId" `
          -Body ($config | ConvertTo-Json -Depth 10) `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $servicePrincipal = $updateResponse | ConvertFrom-Json
      } else {
        # Create new
        $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "POST" `
          -UrlPath "/api/2.0/preview/scim/v2/ServicePrincipals" `
          -Body ($config | ConvertTo-Json -Depth 10) `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $servicePrincipal = $createResponse | ConvertFrom-Json
      }
      
      $DeploymentScriptOutputs = @{
        servicePrincipalId = $servicePrincipal.id
        applicationId = $servicePrincipal.applicationId
        displayName = $servicePrincipal.displayName
        active = $servicePrincipal.active
        externalId = $servicePrincipal.externalId
      }
    '''
  }
}

@description('The ID of the created service principal')
output ServicePrincipalId string = servicePrincipalCreation.properties.outputs.servicePrincipalId

@description('The application ID of the service principal')
output ApplicationId string = servicePrincipalCreation.properties.outputs.applicationId

@description('The display name of the service principal')
output DisplayName string = servicePrincipalCreation.properties.outputs.displayName

@description('Whether the service principal is active')
output Active bool = bool(servicePrincipalCreation.properties.outputs.active)

@description('The external ID of the service principal')
output ExternalId string = servicePrincipalCreation.properties.outputs.externalId
