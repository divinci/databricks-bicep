@description('Cluster ID where the library will be installed')
param ClusterId string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Library specifications to install')
param Libraries array

var libraryConfig = {
  cluster_id: ClusterId
  libraries: Libraries
}

resource libraryInstallation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'install-databricks-libraries-${uniqueString(ClusterId)}'
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
        name: 'LIBRARY_CONFIG'
        value: string(libraryConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Install libraries
      $installResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/libraries/install" `
        -Body $env:LIBRARY_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $config = $env:LIBRARY_CONFIG | ConvertFrom-Json
      
      # Wait for libraries to be installed
      $maxAttempts = 20
      $attempt = 0
      
      do {
        Start-Sleep -Seconds 15
        $attempt++
        
        $statusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
          -Method "GET" `
          -UrlPath "/api/2.0/libraries/cluster-status?cluster_id=$($config.cluster_id)" `
          -DatabricksToken $secureToken `
          -WorkspaceUrl $env:WORKSPACE_URL
        
        $status = $statusResponse | ConvertFrom-Json
        $pendingLibraries = $status.library_statuses | Where-Object { $_.status -in @("PENDING", "INSTALLING") }
        
        Write-Host "Libraries status check (attempt $attempt/$maxAttempts): $($pendingLibraries.Count) pending"
        
        if ($pendingLibraries.Count -eq 0) {
          break
        }
      } while ($attempt -lt $maxAttempts)
      
      # Get final status
      $finalStatusResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/libraries/cluster-status?cluster_id=$($config.cluster_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $finalStatus = $finalStatusResponse | ConvertFrom-Json
      $installedCount = ($finalStatus.library_statuses | Where-Object { $_.status -eq "INSTALLED" }).Count
      $failedCount = ($finalStatus.library_statuses | Where-Object { $_.status -eq "FAILED" }).Count
      
      $DeploymentScriptOutputs = @{
        clusterId = $config.cluster_id
        libraryCount = $config.libraries.Count
        installedCount = $installedCount
        failedCount = $failedCount
        installationComplete = ($attempt -lt $maxAttempts)
      }
    '''
  }
}

@description('The cluster ID where libraries were installed')
output ClusterId string = libraryInstallation.properties.outputs.clusterId

@description('Total number of libraries requested for installation')
output LibraryCount int = int(libraryInstallation.properties.outputs.libraryCount)

@description('Number of libraries successfully installed')
output InstalledCount int = int(libraryInstallation.properties.outputs.installedCount)

@description('Number of libraries that failed to install')
output FailedCount int = int(libraryInstallation.properties.outputs.failedCount)

@description('Whether the installation process completed within the timeout')
output InstallationComplete bool = bool(libraryInstallation.properties.outputs.installationComplete)
