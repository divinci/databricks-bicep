@description('Name of the cluster policy')
param PolicyName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Policy definition as JSON object')
param Definition object

@description('Maximum number of clusters per user (optional)')
param MaxClustersPerUser int = 0

@description('Libraries that are allowed to be installed')
param Libraries array = []

var policyConfig = {
  name: PolicyName
  definition: string(Definition)
  max_clusters_per_user: MaxClustersPerUser == 0 ? null : MaxClustersPerUser
  libraries: empty(Libraries) ? null : Libraries
}

resource policyCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-policy-${uniqueString(PolicyName)}'
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
        name: 'POLICY_CONFIG'
        value: string(policyConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create cluster policy
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/policies/clusters/create" `
        -Body $env:POLICY_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $policy = $createResponse | ConvertFrom-Json
      $policyId = $policy.policy_id
      
      # Get policy details
      $policyDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/policies/clusters/get?policy_id=$policyId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $policyDetails = $policyDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        policyId = $policyId
        policyName = $policyDetails.name
        createdTime = $policyDetails.created_at_timestamp
        creatorUserName = $policyDetails.creator_user_name
      }
    '''
  }
}

@description('The ID of the created cluster policy')
output PolicyId string = policyCreation.properties.outputs.policyId

@description('The name of the created cluster policy')
output PolicyName string = policyCreation.properties.outputs.policyName

@description('The creation timestamp of the policy')
output CreatedTime int = int(policyCreation.properties.outputs.createdTime)

@description('The username of the policy creator')
output CreatorUserName string = policyCreation.properties.outputs.creatorUserName
