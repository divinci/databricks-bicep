@description('Git provider for the credential')
@allowed(['gitHub', 'bitbucketCloud', 'azureDevOpsServices', 'gitLab', 'gitHubEnterprise', 'bitbucketServer', 'azureDevOpsServer', 'gitLabEnterpriseEdition'])
param GitProvider string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Git username')
param GitUsername string = ''

@description('Personal access token for Git provider')
@secure()
param PersonalAccessToken string

var credentialConfig = {
  git_provider: GitProvider
  git_username: empty(GitUsername) ? null : GitUsername
  personal_access_token: PersonalAccessToken
}

resource gitCredentialCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-git-credential-${uniqueString(GitProvider)}'
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
      
      # Create git credential
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/git-credentials" `
        -Body $env:CREDENTIAL_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $credential = $createResponse | ConvertFrom-Json
      
      # Get credential details
      $credentialDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/git-credentials/$($credential.credential_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $credentialDetails = $credentialDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        credentialId = $credentialDetails.credential_id
        gitProvider = $credentialDetails.git_provider
        gitUsername = $credentialDetails.git_username
      }
    '''
  }
}

@description('The ID of the created git credential')
output CredentialId int = int(gitCredentialCreation.properties.outputs.credentialId)

@description('The git provider of the credential')
output GitProvider string = gitCredentialCreation.properties.outputs.gitProvider

@description('The git username of the credential')
output GitUsername string = gitCredentialCreation.properties.outputs.gitUsername
