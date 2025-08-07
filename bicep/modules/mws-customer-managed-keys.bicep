@description('Customer managed key name')
param CustomerManagedKeyName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Account ID for the customer managed key')
param AccountId string

@description('AWS KMS key ID or ARN')
param AwsKeyInfo object

@description('Use cases for the customer managed key')
param UseCases array

var cmkConfig = {
  customer_managed_key_name: CustomerManagedKeyName
  aws_key_info: AwsKeyInfo
  use_cases: UseCases
}

resource mwsCustomerManagedKeysCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-cmk-${uniqueString(CustomerManagedKeyName)}'
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
        name: 'CMK_CONFIG'
        value: string(cmkConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create MWS customer managed key
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/customer-managed-keys" `
        -Body $env:CMK_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $cmk = $createResponse | ConvertFrom-Json
      
      # Get customer managed key details
      $cmkDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$env:ACCOUNT_ID/customer-managed-keys/$($cmk.customer_managed_key_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $cmkDetails = $cmkDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        customerManagedKeyId = $cmkDetails.customer_managed_key_id
        customerManagedKeyName = $cmkDetails.customer_managed_key_name
        awsKeyInfo = ($cmkDetails.aws_key_info | ConvertTo-Json -Compress)
        useCases = ($cmkDetails.use_cases | ConvertTo-Json -Compress)
        accountId = $cmkDetails.account_id
        creationTime = $cmkDetails.creation_time
      }
    '''
  }
}

@description('The customer managed key ID')
output CustomerManagedKeyId string = mwsCustomerManagedKeysCreation.properties.outputs.customerManagedKeyId

@description('The customer managed key name')
output CustomerManagedKeyName string = mwsCustomerManagedKeysCreation.properties.outputs.customerManagedKeyName

@description('The AWS key information')
output AwsKeyInfo string = mwsCustomerManagedKeysCreation.properties.outputs.awsKeyInfo

@description('The use cases for the customer managed key')
output UseCases string = mwsCustomerManagedKeysCreation.properties.outputs.useCases

@description('The account ID')
output AccountId string = mwsCustomerManagedKeysCreation.properties.outputs.accountId

@description('The creation time of the customer managed key')
output CreationTime int = int(mwsCustomerManagedKeysCreation.properties.outputs.creationTime)
