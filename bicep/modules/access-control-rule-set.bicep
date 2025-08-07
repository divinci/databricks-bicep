@description('Name of the access control rule set')
param RuleSetName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Grant rules for the access control rule set')
param GrantRules array = []

@description('Etag for optimistic concurrency control')
param Etag string = ''

var ruleSetConfig = {
  name: RuleSetName
  grant_rules: GrantRules
  etag: empty(Etag) ? null : Etag
}

resource accessControlRuleSetCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-access-control-rule-set-${uniqueString(RuleSetName)}'
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
        name: 'RULE_SET_CONFIG'
        value: string(ruleSetConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create access control rule set
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "PUT" `
        -UrlPath "/api/2.0/permissions/rule-sets" `
        -Body $env:RULE_SET_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $ruleSet = $createResponse | ConvertFrom-Json
      
      # Get rule set details
      $ruleSetDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/permissions/rule-sets/$($ruleSet.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $ruleSetDetails = $ruleSetDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        ruleSetName = $ruleSetDetails.name
        grantRules = ($ruleSetDetails.grant_rules | ConvertTo-Json -Compress)
        etag = $ruleSetDetails.etag
      }
    '''
  }
}

@description('The name of the created access control rule set')
output RuleSetName string = accessControlRuleSetCreation.properties.outputs.ruleSetName

@description('The grant rules of the access control rule set')
output GrantRules string = accessControlRuleSetCreation.properties.outputs.grantRules

@description('The etag of the access control rule set')
output Etag string = accessControlRuleSetCreation.properties.outputs.etag
