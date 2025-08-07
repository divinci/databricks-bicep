@description('Name of the network configuration')
param NetworkName string

@description('Databricks Account ID')
param AccountId string

@description('Databricks Account Token')
@secure()
param AccountToken string

@description('VPC ID for the network')
param VpcId string

@description('Subnet IDs for the network')
param SubnetIds array

@description('Security group IDs for the network')
param SecurityGroupIds array

@description('VPC endpoint ID (optional)')
param VpcEndpointId string = ''

var networkConfig = {
  network_name: NetworkName
  vpc_id: VpcId
  subnet_ids: SubnetIds
  security_group_ids: SecurityGroupIds
  vpc_endpoint_id: empty(VpcEndpointId) ? null : VpcEndpointId
}

resource mwsNetworkCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-network-${uniqueString(NetworkName)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT30M'
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
        name: 'NETWORK_CONFIG'
        value: string(networkConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:ACCOUNT_TOKEN -AsPlainText -Force
      
      # Create MWS network
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/networks" `
        -Body $env:NETWORK_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $network = $createResponse | ConvertFrom-Json
      
      # Get network details
      $networkDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/networks/$($network.network_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $networkDetails = $networkDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        networkId = $networkDetails.network_id
        networkName = $networkDetails.network_name
        vpcId = $networkDetails.vpc_id
        subnetIds = ($networkDetails.subnet_ids -join ",")
        securityGroupIds = ($networkDetails.security_group_ids -join ",")
        vpcEndpointId = $networkDetails.vpc_endpoint_id
        creationTime = $networkDetails.creation_time
      }
    '''
  }
}

@description('The ID of the created network configuration')
output NetworkId string = mwsNetworkCreation.properties.outputs.networkId

@description('The name of the network configuration')
output NetworkName string = mwsNetworkCreation.properties.outputs.networkName

@description('The VPC ID')
output VpcId string = mwsNetworkCreation.properties.outputs.vpcId

@description('The subnet IDs (comma-separated)')
output SubnetIds string = mwsNetworkCreation.properties.outputs.subnetIds

@description('The security group IDs (comma-separated)')
output SecurityGroupIds string = mwsNetworkCreation.properties.outputs.securityGroupIds

@description('The VPC endpoint ID')
output VpcEndpointId string = mwsNetworkCreation.properties.outputs.vpcEndpointId

@description('The creation timestamp of the network configuration')
output CreationTime int = int(mwsNetworkCreation.properties.outputs.creationTime)
