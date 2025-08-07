@description('Name of the Databricks group')
param GroupName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Display name for the group')
param DisplayName string = ''

@description('List of user emails to add to the group')
param Members array = []

@description('List of entitlements for the group')
param Entitlements array = []

@description('External ID for the group (for SCIM)')
param ExternalId string = ''

var groupConfig = {
  displayName: empty(DisplayName) ? GroupName : DisplayName
  members: [for member in Members: {
    value: member
  }]
  entitlements: [for entitlement in Entitlements: {
    value: entitlement
  }]
  externalId: empty(ExternalId) ? null : ExternalId
}

resource groupCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-group-${uniqueString(GroupName)}'
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
        name: 'GROUP_CONFIG'
        value: string(groupConfig)
      }
      {
        name: 'GROUP_NAME'
        value: GroupName
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create group
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/preview/scim/v2/Groups" `
        -Body $env:GROUP_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $group = $createResponse | ConvertFrom-Json
      $groupId = $group.id
      
      # Get group details
      $groupDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/preview/scim/v2/Groups/$groupId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $groupDetails = $groupDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        groupId = $groupId
        groupName = $env:GROUP_NAME
        displayName = $groupDetails.displayName
        memberCount = $groupDetails.members.Count
      }
    '''
  }
}

@description('The ID of the created group')
output GroupId string = groupCreation.properties.outputs.groupId

@description('The name of the created group')
output GroupName string = groupCreation.properties.outputs.groupName

@description('The display name of the group')
output DisplayName string = groupCreation.properties.outputs.displayName

@description('Number of members in the group')
output MemberCount int = int(groupCreation.properties.outputs.memberCount)
