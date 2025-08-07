@description('VPC endpoint name for the MWS VPC endpoint')
param VpcEndpointName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Account ID for the MWS VPC endpoint')
param AccountId string

@description('AWS VPC endpoint ID')
param VpcEndpointId string

@description('AWS region for the VPC endpoint')
param Region string

var vpcEndpointConfig = {
  vpc_endpoint_name: VpcEndpointName
  vpc_endpoint_id: VpcEndpointId
  region: Region
}

resource mwsVpcEndpointCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-vpc-endpoint-${uniqueString(VpcEndpointName)}'
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
        name: 'ACCOUNT_ID'
        value: AccountId
      }
      {
        name: 'VPC_ENDPOINT_CONFIG'
        value: string(vpcEndpointConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MWS VPC endpoint
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/vpc-endpoints" `
        -Body $env:VPC_ENDPOINT_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $vpcEndpoint = $createResponse | ConvertFrom-Json
      
      # Get VPC endpoint details
      $vpcEndpointDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/vpc-endpoints/$($vpcEndpoint.vpc_endpoint_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $vpcEndpointDetails = $vpcEndpointDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        vpcEndpointId = $vpcEndpointDetails.vpc_endpoint_id
        vpcEndpointName = $vpcEndpointDetails.vpc_endpoint_name
        awsVpcEndpointId = $vpcEndpointDetails.aws_vpc_endpoint_id
        region = $vpcEndpointDetails.region
        state = $vpcEndpointDetails.state
        useCase = $vpcEndpointDetails.use_case
        accountId = $vpcEndpointDetails.account_id
      }
    '''
  }
}

@description('The VPC endpoint ID')
output VpcEndpointId string = mwsVpcEndpointCreation.properties.outputs.vpcEndpointId

@description('The VPC endpoint name')
output VpcEndpointName string = mwsVpcEndpointCreation.properties.outputs.vpcEndpointName

@description('The AWS VPC endpoint ID')
output AwsVpcEndpointId string = mwsVpcEndpointCreation.properties.outputs.awsVpcEndpointId

@description('The region of the VPC endpoint')
output Region string = mwsVpcEndpointCreation.properties.outputs.region

@description('The state of the VPC endpoint')
output State string = mwsVpcEndpointCreation.properties.outputs.state

@description('The use case of the VPC endpoint')
output UseCase string = mwsVpcEndpointCreation.properties.outputs.useCase

@description('The account ID of the VPC endpoint')
output AccountId string = mwsVpcEndpointCreation.properties.outputs.accountId
