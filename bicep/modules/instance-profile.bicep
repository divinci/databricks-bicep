@description('Instance profile name')
param InstanceProfileName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Instance profile ARN')
param InstanceProfileArn string

@description('Whether to skip validation')
param SkipValidation bool = false

var profileConfig = {
  instance_profile_arn: InstanceProfileArn
  skip_validation: SkipValidation
}

resource instanceProfileCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-instance-profile-${uniqueString(InstanceProfileName)}'
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
      
      # Add instance profile
      $addResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/instance-profiles/add" `
        -Body $env:PROFILE_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      # List instance profiles to get details
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/instance-profiles/list" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $profiles = $listResponse | ConvertFrom-Json
      $profileConfigObj = $env:PROFILE_CONFIG | ConvertFrom-Json
      $profile = $profiles.instance_profiles | Where-Object { $_.instance_profile_arn -eq $profileConfigObj.instance_profile_arn }
      
      $DeploymentScriptOutputs = @{
        instanceProfileArn = $profile.instance_profile_arn
        isMetaInstanceProfile = $profile.is_meta_instance_profile
      }
    '''
  }
}

@description('The instance profile ARN')
output InstanceProfileArn string = instanceProfileCreation.properties.outputs.instanceProfileArn

@description('Whether this is a meta instance profile')
output IsMetaInstanceProfile bool = bool(instanceProfileCreation.properties.outputs.isMetaInstanceProfile)
