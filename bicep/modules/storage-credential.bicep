@description('Name of the storage credential')
param CredentialName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Comment for the storage credential')
param Comment string = ''

@description('Owner of the storage credential')
param Owner string = ''

@description('Whether the credential is read-only')
param ReadOnly bool = false

@description('Whether to skip validation')
param SkipValidation bool = false

@description('Azure service principal configuration')
param AzureServicePrincipal object = {}

@description('AWS IAM role configuration')
param AwsIamRole object = {}

@description('Databricks GCP service account configuration')
param DatabricksGcpServiceAccount object = {}

var credentialConfig = {
  name: CredentialName
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  read_only: ReadOnly
  skip_validation: SkipValidation
  azure_service_principal: empty(AzureServicePrincipal) ? null : AzureServicePrincipal
  aws_iam_role: empty(AwsIamRole) ? null : AwsIamRole
  databricks_gcp_service_account: empty(DatabricksGcpServiceAccount) ? null : DatabricksGcpServiceAccount
}

resource storageCredentialCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-storage-credential-${uniqueString(CredentialName)}'
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
        name: 'CREDENTIAL_CONFIG'
        value: string(credentialConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create storage credential
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/storage-credentials" `
        -Body $env:CREDENTIAL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $credential = $createResponse | ConvertFrom-Json
      
      # Get credential details
      $credentialDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/storage-credentials/$($credential.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $credentialDetails = $credentialDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        credentialName = $credentialDetails.name
        credentialId = $credentialDetails.id
        owner = $credentialDetails.owner
        comment = $credentialDetails.comment
        readOnly = $credentialDetails.read_only
        createdAt = $credentialDetails.created_at
        updatedAt = $credentialDetails.updated_at
      }
    '''
  }
}

@description('The name of the created storage credential')
output CredentialName string = storageCredentialCreation.properties.outputs.credentialName

@description('The unique ID of the storage credential')
output CredentialId string = storageCredentialCreation.properties.outputs.credentialId

@description('The owner of the storage credential')
output Owner string = storageCredentialCreation.properties.outputs.owner

@description('The comment for the storage credential')
output Comment string = storageCredentialCreation.properties.outputs.comment

@description('Whether the credential is read-only')
output ReadOnly bool = bool(storageCredentialCreation.properties.outputs.readOnly)

@description('The creation timestamp of the storage credential')
output CreatedAt int = int(storageCredentialCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the storage credential')
output UpdatedAt int = int(storageCredentialCreation.properties.outputs.updatedAt)
