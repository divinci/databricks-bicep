@description('Label for the IP access list')
param Label string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Type of the IP access list')
@allowed(['ALLOW', 'BLOCK'])
param ListType string = 'ALLOW'

@description('List of IP ranges')
param IpAddresses array

@description('Whether the list is enabled')
param Enabled bool = true

var accessListConfig = {
  label: Label
  list_type: ListType
  ip_addresses: IpAddresses
  enabled: Enabled
}

resource ipAccessListCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-ip-access-list-${uniqueString(Label)}'
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
        name: 'ACCESS_LIST_CONFIG'
        value: string(accessListConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create IP access list
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/ip-access-lists" `
        -Body $env:ACCESS_LIST_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $accessList = $createResponse | ConvertFrom-Json
      $listId = $accessList.list_id
      
      # Get access list details
      $listDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/ip-access-lists/$listId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $listDetails = $listDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        listId = $listId
        label = $listDetails.label
        listType = $listDetails.list_type
        enabled = $listDetails.enabled
        ipAddressCount = $listDetails.ip_addresses.Count
      }
    '''
  }
}

@description('The ID of the created IP access list')
output ListId string = ipAccessListCreation.properties.outputs.listId

@description('The label of the IP access list')
output Label string = ipAccessListCreation.properties.outputs.label

@description('The type of the IP access list')
output ListType string = ipAccessListCreation.properties.outputs.listType

@description('Whether the IP access list is enabled')
output Enabled bool = bool(ipAccessListCreation.properties.outputs.enabled)

@description('Number of IP addresses in the list')
output IpAddressCount int = int(ipAccessListCreation.properties.outputs.ipAddressCount)
