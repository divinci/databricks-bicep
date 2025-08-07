@description('Spark version key')
param SparkVersionKey string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Whether to include beta versions')
param IncludeBeta bool = false

@description('Whether to include ML runtime versions')
param IncludeMl bool = true

@description('Whether to include Genomics runtime versions')
param IncludeGenomics bool = false

resource sparkVersionCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-databricks-spark-version-${uniqueString(SparkVersionKey)}'
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
        name: 'SPARK_VERSION_KEY'
        value: SparkVersionKey
      }
      {
        name: 'INCLUDE_BETA'
        value: string(IncludeBeta)
      }
      {
        name: 'INCLUDE_ML'
        value: string(IncludeMl)
      }
      {
        name: 'INCLUDE_GENOMICS'
        value: string(IncludeGenomics)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # List Spark versions
      $listResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/clusters/spark-versions" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $sparkVersions = $listResponse | ConvertFrom-Json
      $sparkVersion = $sparkVersions.versions | Where-Object { $_.key -eq $env:SPARK_VERSION_KEY }
      
      if (-not $sparkVersion) {
        throw "Spark version $($env:SPARK_VERSION_KEY) not found"
      }
      
      # Filter based on criteria
      $includeVersion = $true
      
      if ($env:INCLUDE_BETA -eq "False" -and $sparkVersion.name -match "beta") {
        $includeVersion = $false
      }
      
      if ($env:INCLUDE_ML -eq "False" -and $sparkVersion.name -match "ML") {
        $includeVersion = $false
      }
      
      if ($env:INCLUDE_GENOMICS -eq "False" -and $sparkVersion.name -match "Genomics") {
        $includeVersion = $false
      }
      
      if (-not $includeVersion) {
        throw "Spark version $($env:SPARK_VERSION_KEY) does not match filter criteria"
      }
      
      $DeploymentScriptOutputs = @{
        sparkVersionKey = $sparkVersion.key
        sparkVersionName = $sparkVersion.name
        isBeta = ($sparkVersion.name -match "beta")
        isMl = ($sparkVersion.name -match "ML")
        isGenomics = ($sparkVersion.name -match "Genomics")
        isLts = ($sparkVersion.name -match "LTS")
      }
    '''
  }
}

@description('The Spark version key')
output SparkVersionKey string = sparkVersionCreation.properties.outputs.sparkVersionKey

@description('The Spark version name')
output SparkVersionName string = sparkVersionCreation.properties.outputs.sparkVersionName

@description('Whether this is a beta version')
output IsBeta bool = bool(sparkVersionCreation.properties.outputs.isBeta)

@description('Whether this is an ML runtime version')
output IsMl bool = bool(sparkVersionCreation.properties.outputs.isMl)

@description('Whether this is a Genomics runtime version')
output IsGenomics bool = bool(sparkVersionCreation.properties.outputs.isGenomics)

@description('Whether this is an LTS version')
output IsLts bool = bool(sparkVersionCreation.properties.outputs.isLts)
