BeforeAll {
    # Import required modules
    Import-Module Pester -Force
    
    # Test configuration
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks Cluster Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a cluster with minimum required parameters" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-cluster-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            # Deploy the template
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ClusterName.Value | Should -Be $parameters.ClusterName
            $deployment.Outputs.State.Value | Should -Be "RUNNING"
            
            # Store cluster ID for cleanup
            $script:CreatedClusterId = $deployment.Outputs.ClusterId.Value
        }
        
        It "Should create an autoscaling cluster" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-autoscale-cluster-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AutoScale = $true
                MinWorkers = 1
                MaxWorkers = 4
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.State.Value | Should -Be "RUNNING"
            
            # Store cluster ID for cleanup
            $script:CreatedAutoscaleClusterId = $deployment.Outputs.ClusterId.Value
        }
        
        It "Should create a cluster with custom configuration" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-custom-cluster-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SparkVersion = "12.2.x-scala2.12"
                NodeTypeId = "Standard_DS4_v2"
                NumWorkers = 3
                AutoTerminationMinutes = 120
                CustomTags = @{
                    Environment = "Test"
                    Project = "BicepConversion"
                }
                SparkConf = @{
                    "spark.sql.adaptive.enabled" = "true"
                    "spark.sql.adaptive.coalescePartitions.enabled" = "true"
                }
                RuntimeEngine = "PHOTON"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.SparkVersion.Value | Should -Be $parameters.SparkVersion
            $deployment.Outputs.NodeTypeId.Value | Should -Be $parameters.NodeTypeId
            $deployment.Outputs.NumWorkers | Should -Be $parameters.NumWorkers
            
            # Store cluster ID for cleanup
            $script:CreatedCustomClusterId = $deployment.Outputs.ClusterId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid Spark version" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-invalid-cluster"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SparkVersion = "invalid-version"
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
        
        It "Should fail with invalid node type" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-invalid-node-cluster"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                NodeTypeId = "Invalid_Node_Type"
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
        
        It "Should fail with invalid autoscale configuration" {
            $templateFile = "$PSScriptRoot/../modules/cluster.bicep"
            $parameters = @{
                ClusterName = "test-invalid-autoscale-cluster"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AutoScale = $true
                MinWorkers = 5
                MaxWorkers = 2
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
}

AfterAll {
    # Cleanup created clusters
    if ($script:CreatedClusterId) {
        Write-Host "Cleaning up cluster: $($script:CreatedClusterId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/clusters/permanent-delete" `
                -Body "{`"cluster_id`": `"$($script:CreatedClusterId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup cluster $($script:CreatedClusterId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAutoscaleClusterId) {
        Write-Host "Cleaning up autoscale cluster: $($script:CreatedAutoscaleClusterId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/clusters/permanent-delete" `
                -Body "{`"cluster_id`": `"$($script:CreatedAutoscaleClusterId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup autoscale cluster $($script:CreatedAutoscaleClusterId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedCustomClusterId) {
        Write-Host "Cleaning up custom cluster: $($script:CreatedCustomClusterId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/clusters/permanent-delete" `
                -Body "{`"cluster_id`": `"$($script:CreatedCustomClusterId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup custom cluster $($script:CreatedCustomClusterId): $($_.Exception.Message)"
        }
    }
}
