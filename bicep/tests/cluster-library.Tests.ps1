BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test cluster first
    $script:TestClusterId = ""
}

Describe "Databricks Cluster Library Bicep Module Tests" {
    BeforeAll {
        # Create a test cluster for library installation
        Write-Host "Creating test cluster for library tests"
        $clusterConfig = @{
            cluster_name = "test-library-cluster-$(Get-Random)"
            spark_version = "13.3.x-scala2.12"
            node_type_id = "i3.xlarge"
            num_workers = 1
            autotermination_minutes = 30
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/clusters/create" `
                -Body $clusterConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $clusterResult = $createResponse | ConvertFrom-Json
            $script:TestClusterId = $clusterResult.cluster_id
            Write-Host "Created test cluster with ID: $($script:TestClusterId)"
        }
        catch {
            Write-Warning "Failed to create test cluster: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should install a PyPI library on cluster" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Library = @{
                    pypi = @{
                        package = "requests==2.28.1"
                    }
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Be $script:TestClusterId
            $deployment.Outputs.LibraryStatuses.Value | Should -Not -BeNullOrEmpty
            
            $script:InstalledPypiLibrary = $true
        }
        
        It "Should install a Maven library on cluster" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Library = @{
                    maven = @{
                        coordinates = "org.apache.spark:spark-avro_2.12:3.4.0"
                    }
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.LibraryStatuses.Value | Should -Match "maven"
            
            $script:InstalledMavenLibrary = $true
        }
        
        It "Should install a JAR library on cluster" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Library = @{
                    jar = "dbfs:/FileStore/jars/test-library.jar"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.LibraryStatuses.Value | Should -Match "jar"
            
            $script:InstalledJarLibrary = $true
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty cluster ID" {
            $templateFile = "$PSScriptRoot/../modules/cluster-library.bicep"
            $parameters = @{
                ClusterId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Library = @{
                    pypi = @{
                        package = "requests"
                    }
                }
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should fail with empty library specification" {
            $templateFile = "$PSScriptRoot/../modules/cluster-library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Library = @{}
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
    
    AfterAll {
        # Cleanup libraries (uninstall them)
        if ($script:TestClusterId -and ($script:InstalledPypiLibrary -or $script:InstalledMavenLibrary -or $script:InstalledJarLibrary)) {
            Write-Host "Cleaning up libraries from cluster: $($script:TestClusterId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                
                # Uninstall all libraries
                $uninstallConfig = @{
                    cluster_id = $script:TestClusterId
                    libraries = @(
                        @{ pypi = @{ package = "requests==2.28.1" } },
                        @{ maven = @{ coordinates = "org.apache.spark:spark-avro_2.12:3.4.0" } },
                        @{ jar = "dbfs:/FileStore/jars/test-library.jar" }
                    )
                } | ConvertTo-Json -Depth 10
                
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/libraries/uninstall" `
                    -Body $uninstallConfig `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup libraries: $($_.Exception.Message)"
            }
        }
        
        # Cleanup test cluster
        if ($script:TestClusterId) {
            Write-Host "Cleaning up test cluster: $($script:TestClusterId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/clusters/permanent-delete" `
                    -Body (@{ cluster_id = $script:TestClusterId } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test cluster: $($_.Exception.Message)"
            }
        }
    }
}
