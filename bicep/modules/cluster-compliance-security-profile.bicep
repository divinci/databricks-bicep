@description('Cluster ID for the compliance security profile')
param ClusterId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether compliance security profile is enabled')
param IsEnabled bool = true

@description('Compliance standards to enforce')
param ComplianceStandards array = []

var profileConfig = {
  cluster_id: ClusterId
  is_enabled: IsEnabled
  compliance_standards: ComplianceStandards
}

resource clusterComplianceSecurityProfileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-cluster-compliance-${uniqueString(ClusterId)}'
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
        name: 'PROFILE_CONFIG'
        value: string(profileConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      $profileConfigObj = $env:PROFILE_CONFIG | ConvertFrom-Json
      
      # Update cluster compliance security profile
      $updateResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/clusters/compliance-security-profile" `
        -Body $env:PROFILE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # Get cluster compliance security profile
      $profileResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/clusters/compliance-security-profile?cluster_id=$($profileConfigObj.cluster_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $profile = $profileResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        clusterId = $profile.cluster_id
        isEnabled = $profile.is_enabled
        complianceStandards = ($profile.compliance_standards | ConvertTo-Json -Compress)
      }
    '''
  }
}

@description('The cluster ID')
output ClusterId string = clusterComplianceSecurityProfileCreation.properties.outputs.clusterId

@description('Whether compliance security profile is enabled')
output IsEnabled bool = bool(clusterComplianceSecurityProfileCreation.properties.outputs.isEnabled)

@description('The compliance standards enforced')
output ComplianceStandards string = clusterComplianceSecurityProfileCreation.properties.outputs.complianceStandards
