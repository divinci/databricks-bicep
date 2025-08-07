@description('Name of the Databricks workspace')
param WorkspaceName string

@description('Databricks Account ID')
param AccountId string

@description('Databricks Account Token')
@secure()
param AccountToken string

@description('AWS region for the workspace')
param AwsRegion string

@description('Credentials ID for the workspace')
param CredentialsId string

@description('Storage configuration ID for the workspace')
param StorageConfigurationId string

@description('Network ID for the workspace (optional)')
param NetworkId string = ''

@description('Customer managed key ID (optional)')
param CustomerManagedKeyId string = ''

@description('Pricing tier for the workspace')
@allowed(['STANDARD', 'PREMIUM'])
param PricingTier string = 'PREMIUM'

@description('Deployment name for the workspace')
param DeploymentName string = ''

@description('Whether to enable HIPAA compliance')
param IsNoPublicIpEnabled bool = false

@description('Custom tags for the workspace')
param CustomTags object = {}

var workspaceConfig = {
  workspace_name: WorkspaceName
  aws_region: AwsRegion
  credentials_id: CredentialsId
  storage_configuration_id: StorageConfigurationId
  network_id: empty(NetworkId) ? null : NetworkId
  customer_managed_key_id: empty(CustomerManagedKeyId) ? null : CustomerManagedKeyId
  pricing_tier: PricingTier
  deployment_name: empty(DeploymentName) ? WorkspaceName : DeploymentName
  is_no_public_ip_enabled: IsNoPublicIpEnabled
  custom_tags: empty(CustomTags) ? {} : CustomTags
}

resource mwsWorkspaceCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-workspace-${uniqueString(WorkspaceName)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT60M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'ACCOUNT_TOKEN'
        secureValue: AccountToken
      }
      {
        name: 'ACCOUNT_ID'
        value: AccountId
      }
      {
        name: 'WORKSPACE_CONFIG'
        value: string(workspaceConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:ACCOUNT_TOKEN -AsPlainText -Force
      
      # Create MWS workspace
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/workspaces" `
        -Body $env:WORKSPACE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $workspace = $createResponse | ConvertFrom-Json
      $workspaceId = $workspace.workspace_id
      
      # Wait for workspace to be running (with timeout)
      $maxWaitTime = 1800  # 30 minutes
      $waitTime = 0
      $sleepInterval = 30
      
      do {
        Start-Sleep -Seconds $sleepInterval
        $waitTime += $sleepInterval
        
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/workspaces/$workspaceId" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl "https://accounts.cloud.databricks.com"
        
        $workspaceDetails = $statusResponse | ConvertFrom-Json
        $status = $workspaceDetails.workspace_status
        
        Write-Host "Workspace status: $status (waited $waitTime seconds)"
        
        if ($status -eq "RUNNING") {
          break
        }
        
        if ($status -eq "FAILED") {
          throw "Workspace creation failed"
        }
        
      } while ($waitTime -lt $maxWaitTime)
      
      if ($waitTime -ge $maxWaitTime) {
        Write-Warning "Workspace creation timed out, but continuing..."
      }
      
      $DeploymentScriptOutputs = @{
        workspaceId = $workspaceDetails.workspace_id
        workspaceName = $workspaceDetails.workspace_name
        workspaceUrl = $workspaceDetails.deployment_name + ".cloud.databricks.com"
        workspaceStatus = $workspaceDetails.workspace_status
        awsRegion = $workspaceDetails.aws_region
        pricingTier = $workspaceDetails.pricing_tier
        creationTime = $workspaceDetails.creation_time
      }
    '''
  }
}

@description('The ID of the created workspace')
output WorkspaceId int = int(mwsWorkspaceCreation.properties.outputs.workspaceId)

@description('The name of the workspace')
output WorkspaceName string = mwsWorkspaceCreation.properties.outputs.workspaceName

@description('The URL of the workspace')
output WorkspaceUrl string = mwsWorkspaceCreation.properties.outputs.workspaceUrl

@description('The status of the workspace')
output WorkspaceStatus string = mwsWorkspaceCreation.properties.outputs.workspaceStatus

@description('The AWS region of the workspace')
output AwsRegion string = mwsWorkspaceCreation.properties.outputs.awsRegion

@description('The pricing tier of the workspace')
output PricingTier string = mwsWorkspaceCreation.properties.outputs.pricingTier

@description('The creation timestamp of the workspace')
output CreationTime int = int(mwsWorkspaceCreation.properties.outputs.creationTime)
