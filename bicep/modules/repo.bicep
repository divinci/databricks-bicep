@description('Path where the repo will be cloned in Databricks workspace')
param RepoPath string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Git repository URL')
param Url string

@description('Git provider')
@allowed(['gitHub', 'bitbucketCloud', 'azureDevOpsServices', 'gitLab', 'gitHubEnterprise', 'bitbucketServer', 'azureDevOpsServer', 'gitLabEnterpriseEdition'])
param Provider string = 'gitHub'

@description('Branch to checkout')
param Branch string = 'main'

@description('Tag to checkout (alternative to branch)')
param Tag string = ''

var repoConfig = {
  url: Url
  provider: Provider
  path: RepoPath
  branch: empty(Tag) ? Branch : null
  tag: empty(Tag) ? null : Tag
}

resource repoCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-repo-${uniqueString(RepoPath)}'
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
        name: 'REPO_CONFIG'
        value: string(repoConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create repo
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/repos" `
        -Body $env:REPO_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $repo = $createResponse | ConvertFrom-Json
      $repoId = $repo.id
      
      # Get repo details
      $repoDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/repos/$repoId" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $repoDetails = $repoDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        repoId = $repoId
        repoPath = $repoDetails.path
        url = $repoDetails.url
        provider = $repoDetails.provider
        branch = $repoDetails.branch
        headCommitId = $repoDetails.head_commit_id
      }
    '''
  }
}

@description('The ID of the created repo')
output RepoId int = int(repoCreation.properties.outputs.repoId)

@description('The path of the repo in the workspace')
output RepoPath string = repoCreation.properties.outputs.repoPath

@description('The Git repository URL')
output Url string = repoCreation.properties.outputs.url

@description('The Git provider')
output Provider string = repoCreation.properties.outputs.provider

@description('The current branch')
output Branch string = repoCreation.properties.outputs.branch

@description('The head commit ID')
output HeadCommitId string = repoCreation.properties.outputs.headCommitId
