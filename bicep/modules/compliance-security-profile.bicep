@description('Compliance security profile name')
param ProfileName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether the compliance security profile is enabled')
param IsEnabled bool = true

@description('Compliance standards to enforce')
param ComplianceStandards array = []

@description('Security controls configuration')
param SecurityControls object = {}

var profileConfig = {
  profile_name: ProfileName
  is_enabled: IsEnabled
  compliance_standards: ComplianceStandards
  security_controls: SecurityControls
}

resource complianceSecurityProfileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-compliance-profile-${uniqueString(ProfileName)}'
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
      
      # Create compliance security profile
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/workspace/compliance-security-profiles" `
        -Body $env:PROFILE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $profile = $createResponse | ConvertFrom-Json
      
      # Get compliance security profile details
      $profileDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/workspace/compliance-security-profiles/$($profile.profile_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $profileDetails = $profileDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        profileId = $profileDetails.profile_id
        profileName = $profileDetails.profile_name
        isEnabled = $profileDetails.is_enabled
        complianceStandards = ($profileDetails.compliance_standards | ConvertTo-Json -Compress)
        securityControls = ($profileDetails.security_controls | ConvertTo-Json -Compress)
        createdAt = $profileDetails.created_at
        updatedAt = $profileDetails.updated_at
      }
    '''
  }
}

@description('The compliance security profile ID')
output ProfileId string = complianceSecurityProfileCreation.properties.outputs.profileId

@description('The compliance security profile name')
output ProfileName string = complianceSecurityProfileCreation.properties.outputs.profileName

@description('Whether the compliance security profile is enabled')
output IsEnabled bool = bool(complianceSecurityProfileCreation.properties.outputs.isEnabled)

@description('The compliance standards enforced')
output ComplianceStandards string = complianceSecurityProfileCreation.properties.outputs.complianceStandards

@description('The security controls configuration')
output SecurityControls string = complianceSecurityProfileCreation.properties.outputs.securityControls

@description('The creation timestamp')
output CreatedAt int = int(complianceSecurityProfileCreation.properties.outputs.createdAt)

@description('The last updated timestamp')
output UpdatedAt int = int(complianceSecurityProfileCreation.properties.outputs.updatedAt)
