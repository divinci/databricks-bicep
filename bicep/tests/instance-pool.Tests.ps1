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

Describe "Databricks Instance Pool Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an instance pool with minimum required parameters" {
            $templateFile = "$PSScriptRoot/../modules/instance-pool.bicep"
            $parameters = @{
                InstancePoolName = "test-pool-$(Get-Random)"
                NodeTypeId = "Standard_DS3_v2"
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
            $deployment.Outputs.InstancePoolId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.InstancePoolName.Value | Should -Be $parameters.InstancePoolName
            $deployment.Outputs.NodeTypeId.Value | Should -Be $parameters.NodeTypeId
            $deployment.Outputs.State.Value | Should -Be "ACTIVE"
            
            # Store instance pool ID for cleanup
            $script:CreatedInstancePoolId = $deployment.Outputs.InstancePoolId.Value
        }
        
        It "Should create an instance pool with custom configuration" {
            $templateFile = "$PSScriptRoot/../modules/instance-pool.bicep"
            $parameters = @{
                InstancePoolName = "test-custom-pool-$(Get-Random)"
                NodeTypeId = "Standard_DS4_v2"
                MinIdleInstances = 2
                MaxCapacity = 20
                IdleInstanceAutoTerminationMinutes = 120
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CustomTags = @{
                    Environment = "Test"
                    Project = "BicepConversion"
                }
                PreloadedSparkVersions = @("13.3.x-scala2.12", "12.2.x-scala2.12")
                EnableElasticDisk = $true
                DiskSpec = @{
                    disk_type = @{
                        azure_disk_volume_type = "PREMIUM_LRS"
                    }
                    disk_size = 100
                    disk_count = 1
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.InstancePoolId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.MinIdleInstances.Value | Should -Be $parameters.MinIdleInstances
            $deployment.Outputs.MaxCapacity.Value | Should -Be $parameters.MaxCapacity
            $deployment.Outputs.IdleInstanceAutoTerminationMinutes.Value | Should -Be $parameters.IdleInstanceAutoTerminationMinutes
            
            # Store instance pool ID for cleanup
            $script:CreatedCustomInstancePoolId = $deployment.Outputs.InstancePoolId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid node type" {
            $templateFile = "$PSScriptRoot/../modules/instance-pool.bicep"
            $parameters = @{
                InstancePoolName = "test-invalid-pool"
                NodeTypeId = "Invalid_Node_Type"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
        
        It "Should fail with invalid capacity configuration" {
            $templateFile = "$PSScriptRoot/../modules/instance-pool.bicep"
            $parameters = @{
                InstancePoolName = "test-invalid-capacity-pool"
                NodeTypeId = "Standard_DS3_v2"
                MinIdleInstances = 10
                MaxCapacity = 5
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
    # Cleanup created instance pools
    if ($script:CreatedInstancePoolId) {
        Write-Host "Cleaning up instance pool: $($script:CreatedInstancePoolId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/instance-pools/delete" `
                -Body "{`"instance_pool_id`": `"$($script:CreatedInstancePoolId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup instance pool $($script:CreatedInstancePoolId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedCustomInstancePoolId) {
        Write-Host "Cleaning up custom instance pool: $($script:CreatedCustomInstancePoolId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/instance-pools/delete" `
                -Body "{`"instance_pool_id`": `"$($script:CreatedCustomInstancePoolId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup custom instance pool $($script:CreatedCustomInstancePoolId): $($_.Exception.Message)"
        }
    }
}
