@description('Name of the credentials configuration')
param CredentialsName string

@description('Databricks Account ID')
param AccountId string

@description('Databricks Account Token')
@secure()
param AccountToken string

@description('AWS IAM role ARN for cross-account access')
param RoleArn string

@description('External ID for the IAM role')
param ExternalId string = ''

var credentialsConfig = {
  credentials_name: CredentialsName
  aws_credentials: {
    sts_role: {
      role_arn: RoleArn
      external_id: empty(ExternalId) ? null : ExternalId
    }
  }
}

resource mwsCredentialsCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-mws-credentials-${uniqueString(CredentialsName)}'
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
        name: 'CREDENTIALS_CONFIG'
        value: string(credentialsConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:ACCOUNT_TOKEN -AsPlainText -Force
      
      # Create MWS credentials
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/credentials" `
        -Body $env:CREDENTIALS_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $credentials = $createResponse | ConvertFrom-Json
      
      # Get credentials details
      $credentialsDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/$($env:ACCOUNT_ID)/credentials/$($credentials.credentials_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl "https://accounts.cloud.databricks.com"
      
      $credentialsDetails = $credentialsDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        credentialsId = $credentialsDetails.credentials_id
        credentialsName = $credentialsDetails.credentials_name
        roleArn = $credentialsDetails.aws_credentials.sts_role.role_arn
        externalId = $credentialsDetails.aws_credentials.sts_role.external_id
        creationTime = $credentialsDetails.creation_time
      }
    '''
  }
}

@description('The ID of the created credentials configuration')
output CredentialsId string = mwsCredentialsCreation.properties.outputs.credentialsId

@description('The name of the credentials configuration')
output CredentialsName string = mwsCredentialsCreation.properties.outputs.credentialsName

@description('The IAM role ARN')
output RoleArn string = mwsCredentialsCreation.properties.outputs.roleArn

@description('The external ID for the IAM role')
output ExternalId string = mwsCredentialsCreation.properties.outputs.externalId

@description('The creation timestamp of the credentials')
output CreationTime int = int(mwsCredentialsCreation.properties.outputs.creationTime)
