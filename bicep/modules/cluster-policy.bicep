@description('Name of the cluster policy')
param PolicyName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Policy definition as JSON string')
param Definition string

@description('Description of the policy')
param Description string = ''

@description('Maximum number of clusters per user')
param MaxClustersPerUser int = 0

@description('Policy family ID')
param PolicyFamilyId string = ''

@description('Policy family definition overrides')
param PolicyFamilyDefinitionOverrides string = ''

@description('Libraries to install on clusters using this policy')
param Libraries array = []

var policyConfig = {
  name: PolicyName
  definition: Definition
  description: empty(Description) ? null : Description
  max_clusters_per_user: MaxClustersPerUser == 0 ? null : MaxClustersPerUser
  policy_family_id: empty(PolicyFamilyId) ? null : PolicyFamilyId
  policy_family_definition_overrides: empty(PolicyFamilyDefinitionOverrides) ? null : PolicyFamilyDefinitionOverrides
  libraries: Libraries
}

resource clusterPolicyCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-cluster-policy-${uniqueString(PolicyName)}'
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
      
      # Get policy details
      $policyDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/policies/clusters/get?policy_id=$($policy.policy_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $policyDetails = $policyDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        policyId = $policyDetails.policy_id
        policyName = $policyDetails.name
        definition = $policyDetails.definition
        description = $policyDetails.description
        maxClustersPerUser = $policyDetails.max_clusters_per_user
        policyFamilyId = $policyDetails.policy_family_id
        policyFamilyDefinitionOverrides = $policyDetails.policy_family_definition_overrides
        createdAtTimestamp = $policyDetails.created_at_timestamp
        creatorUserName = $policyDetails.creator_user_name
      }
    '''
  }
}

@description('The ID of the created cluster policy')
output PolicyId string = clusterPolicyCreation.properties.outputs.policyId

@description('The name of the cluster policy')
output PolicyName string = clusterPolicyCreation.properties.outputs.policyName

@description('The definition of the cluster policy')
output Definition string = clusterPolicyCreation.properties.outputs.definition

@description('The description of the cluster policy')
output Description string = clusterPolicyCreation.properties.outputs.description

@description('The maximum clusters per user')
output MaxClustersPerUser int = int(clusterPolicyCreation.properties.outputs.maxClustersPerUser)

@description('The policy family ID')
output PolicyFamilyId string = clusterPolicyCreation.properties.outputs.policyFamilyId

@description('The policy family definition overrides')
output PolicyFamilyDefinitionOverrides string = clusterPolicyCreation.properties.outputs.policyFamilyDefinitionOverrides

@description('The creation timestamp of the cluster policy')
output CreatedAtTimestamp int = int(clusterPolicyCreation.properties.outputs.createdAtTimestamp)

@description('The creator username of the cluster policy')
output CreatorUserName string = clusterPolicyCreation.properties.outputs.creatorUserName
