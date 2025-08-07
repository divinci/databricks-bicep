BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test cluster for library installation
    $script:TestClusterId = $null
}

Describe "Databricks Library Bicep Module Tests" {
    BeforeAll {
        # Create a test cluster first
        Write-Host "Creating test cluster for library installation..."
        $clusterConfig = @{
            cluster_name = "test-library-cluster-$(Get-Random)"
            spark_version = "13.3.x-scala2.12"
            node_type_id = "Standard_DS3_v2"
            num_workers = 1
            auto_termination_minutes = 30
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/clusters/create" `
                -Body $clusterConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $cluster = $createResponse | ConvertFrom-Json
            $script:TestClusterId = $cluster.cluster_id
            Write-Host "Created test cluster: $($script:TestClusterId)"
            
            # Wait for cluster to be ready
            $maxAttempts = 20
            $attempt = 0
            do {
                Start-Sleep -Seconds 30
                $attempt++
                
                $statusResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "GET" `
                    -UrlPath "/api/2.1/clusters/get?cluster_id=$($script:TestClusterId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
                
                $status = ($statusResponse | ConvertFrom-Json).state
                Write-Host "Cluster status: $status (attempt $attempt/$maxAttempts)"
                
                if ($status -eq "RUNNING") {
                    break
                }
            } while ($attempt -lt $maxAttempts -and $status -notin @("ERROR", "TERMINATED"))
            
            if ($status -ne "RUNNING") {
                throw "Test cluster failed to start: $status"
            }
        }
        catch {
            Write-Error "Failed to create test cluster: $($_.Exception.Message)"
            throw
        }
    }
    
    Context "Positive Path Tests" {
        It "Should install PyPI libraries on cluster" -Skip:($null -eq $script:TestClusterId) {
            $templateFile = "$PSScriptRoot/../modules/library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @(
                    @{
                        pypi = @{
                            package = "requests==2.28.2"
                        }
                    },
                    @{
                        pypi = @{
                            package = "numpy==1.24.3"
                        }
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Be $script:TestClusterId
            $deployment.Outputs.LibraryCount.Value | Should -Be 2
            $deployment.Outputs.InstallationComplete.Value | Should -Be $true
        }
        
        It "Should install Maven libraries on cluster" -Skip:($null -eq $script:TestClusterId) {
            $templateFile = "$PSScriptRoot/../modules/library.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @(
                    @{
                        maven = @{
                            coordinates = "com.amazonaws:aws-java-sdk-s3:1.12.261"
                        }
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.LibraryCount.Value | Should -Be 1
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid cluster ID" {
            $templateFile = "$PSScriptRoot/../modules/library.bicep"
            $parameters = @{
                ClusterId = "invalid-cluster-id"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @(
                    @{
                        pypi = @{
                            package = "requests"
                        }
                    }
                )
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
        # Cleanup test cluster
        if ($script:TestClusterId) {
            Write-Host "Cleaning up test cluster: $($script:TestClusterId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.1/clusters/permanent-delete" `
                    -Body "{`"cluster_id`": `"$($script:TestClusterId)`"}" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test cluster $($script:TestClusterId): $($_.Exception.Message)"
            }
        }
    }
}
